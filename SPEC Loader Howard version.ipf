#pragma rtGlobals=3				// Use modern global access method and strict wave access.
#pragma IgorVersion = 7.00		// FGetPos requires Igor7

// Loads the data from a SPEC file.
// See http://www.certif.com/content/spec/
// See "Standard Data File Format" in https://certif.com/downloads/css_docs/spec_man.pdf
// And see http://www.esrf.eu/UsersAndScience/Experiments/MX/About_our_beamlines/Beamline_Components

// Adds a "Load SPEC File" item to the Data->Load Waves menu.
// For each file a main data folder is created.
// For each data section in the file a sub-data folder is created.
// If you are not familiar with data folders, execute this:
//		DisplayHelpTopic "Data Folders"

// 2019-06-03 Changes
//
// Use FGetPos instead of FStatus which is very slow. This requires Igor Pro 7.00 or later.
//
// Handle names containing a single space such as "Two Theta". Search for "Two Theta" for details.
//
// Replaced LoadWave with homebrew loader based on FReadLine in order to support
// comments embedded in data blocks. See See "Standard Data File Format" in spec_man.pdf.
//
//	Data is now loaded as double precision instead of single precision.
//
// Changed data folder names from Section0,Section1,... to Scan1,Scan2...

// This procedure file illustrates how to use FReadLine to parse a complex file
// and to load header information and numeric data.
// To see how it works, read the comments below. Start from the high-level
// function LoadSPECFile, which is at the bottom of the file. After reading
// the comments and code for LoadSPECFile, read the comments and
// code for the lower-level subroutines that it calls

Menu "Load Waves"
	"Load SPEC File...", LoadSPECFile("", "")
End

// MakeSPECCatalog(refNum)
// Returns a 2D wave describing the sections of a file.
//	Column 0: File position of start of section (#S tag)
//	Column 1: Line number of start of section (#S tag)
//	Column 2: Line number of column names line (#L tag)
//	Column 3: Line number of start of data
//	Column 4: Line number of last line of data
// All line numbers are zero-based.
// Each section of the file looks like this:
//	#S <Scan Number>
//	<Various Header Lines>
//	#L <Column Names>
//	<data line 0>
//	<data line 1>
//	...						// The data block can include comments introduces by "#C"
//	<data line n>
//	<End of Section>
// <End of Section> is a control line or a blank line or the end-of-file.
static Function/WAVE MakeSPECCatalog(refNum)
	Variable refNum			// File reference number from Open command

	// The information about the file is returned in this wave
	Make /O /N=(0,6) SPECCatalog
	SetDimLabel 1, 0, SectionStartFPos, SPECCatalog	// Column 0 contains the section file position
	SetDimLabel 1, 1, SectionStartLine, SPECCatalog		// Column 1 contains the section start line number
	SetDimLabel 1, 2, ColumnNamesFPos, SPECCatalog	// Column 2 contains the column names file position
	SetDimLabel 1, 3, ColumnNamesLine, SPECCatalog	// Column 3 contains the column names line number
	SetDimLabel 1, 4, DataStartLine, SPECCatalog		// Column 5 contains the data start line number
	SetDimLabel 1, 5, DataEndLine, SPECCatalog		// Column 6 contains the data end line number

	String text
	
	Variable numSections = 0
	Variable sectionNumber = -1	// No sections yet
	Variable inData = 0

	Variable lineNumber = 0
	do
		Variable fPos
		FGetPos refNum				// HR, 2019-06-03: Use FGetPos instead of FStatus which is very slow
		fPos = V_FilePos			// Current file position for the file in bytes from the start
		
		FReadLine refNum, text
		if (strlen(text) == 0)
			SPECCatalog[sectionNumber][%DataEndLine] = lineNumber-1	// HR, 2019-06-03: Added this
			break					// Reached end-of-file
		endif
		
		if (CmpStr(text[0,1], "#S") == 0)
			// Start of section
			sectionNumber += 1							// Start of new section
			InsertPoints numSections, 1, SPECCatalog		// Add row for new section
			numSections += 1
			SPECCatalog[sectionNumber][] = NaN
			SPECCatalog[sectionNumber][%SectionStartFPos] = fPos
			SPECCatalog[sectionNumber][%SectionStartLine] = lineNumber
		endif
		if (CmpStr(text[0,1], "#L") == 0)
			SPECCatalog[sectionNumber][%ColumnNamesFPos] = fPos
			SPECCatalog[sectionNumber][%ColumnNamesLine] = lineNumber
			// We assume that the data starts immediately after #L
			SPECCatalog[sectionNumber][%DataStartLine] = lineNumber+1
			inData = 1
		else
			if (inData)
				Variable dummy
				sscanf text, "%g", dummy		// Does line start with a number?
				if (V_flag > 0)
					// Line starts with a number so this may be the last data line
					SPECCatalog[sectionNumber][%DataEndLine] = lineNumber		// Provisional last data line
				else
					if (CmpStr(text[0,1], "#C") == 0)
						// A comment can appear in the data block. We have to examine
						// successive lines to determine if the data block is finished.
					else
						// This should be a control line other than a comment or a blank line.
						// In either case, the data block is finished.
						inData = 0
					endif
				endif
			endif
		endif
		
		lineNumber += 1
	while(1)
	
	Redimension /N=(numSections,6) SPECCatalog
	
	return SPECCatalog	
End

static Function SkipSpaces(text, len, pos)
	String text
	Variable len
	Variable pos
	
	Variable i
	for(i=0; i<len; i+=1)
		if (CmpStr(text[pos]," ") != 0)
			break
		else
			pos += 1
		endif
	endfor
	return pos
End

// LoadSPECHeader(refNum, sectionStartFPos, sectionStartLine)
// Loads each header line into a global variable in the current data folder.
// Each variable name starts with "Header" and ends with the tag name.
// So you get, for example:
//	HeaderStrS
//	HeaderStrD
//	HeaderStrT
//	HeaderStrG0
//	HeaderStrG1
//	HeaderStrG2
// Currently each header line is loaded into a string variable which can be parsed as needed.
// LoadSPECHeader leaves the file position at the start of the line after the header lines.
static Function LoadSPECHeader(refNum, sectionStartFPos, sectionStartLine)
	Variable refNum					// File reference number from Open command
	Variable sectionStartFPos
	Variable sectionStartLine
	
	FSetPos refNum, sectionStartFPos
	
	do
		String text
		FReadLine refNum, text
		Variable len = strlen(text)
		String tagName					// e.g., "#S, #D, #T, #G0, . . .
		sscanf text, "%s", tagName
		
		if (CmpStr(tagName, "#L") == 0)			// Reached column labels?
			break
		endif		
		
		Variable pos = SkipSpaces(text, len, strlen(tagName))	// Skip past tag and trailing spaces
		String tagText = text[pos,len-1]
		String varName = "HeaderStr" + tagName				// e.g., HeaderStr#G0
		varName = ReplaceString("#", varName, "")				// e.g., HeaderStrG0
		String/G $varName = tagText
	while(1)

	return 0
End

// GetSPECSectionNameList(refNum, columnNamesFPos)
// Returns a semicolon-separated list of column names.
// The name line in the section looks something like this:
//	#L Time Epoch Ioni1 Ioni2 Ioni3 Absorption Reference FluoW_1 FluoW_2 FluoW_3 FluoW_4 FluoW_5 ICR_1 ICR_2 ICR_3 ICR_4 ICR_5 OCR_1 OCR_2 OCR_3 OCR_4 OCR_5 DEAD_1 DEAD_2 DEAD_3 DEAD_4 DEAD_5 FLUO e-Current FLUO_I0 Pindiode Seconds Seconds
// There may be multiple spaces between names.
static Function/S GetSPECSectionNameList(refNum, columnNamesFPos)
	Variable refNum					// File reference number from Open command
	Variable columnNamesFPos
	
	FSetPos refNum, columnNamesFPos
	
	String text
	FReadLine refNum, text
	text = RemoveEnding(text, "\r")
	Variable len = strlen(text)
	
	String list = ""
	
	Variable pos = 0
	Variable numNames = 0
	
	do
		Variable origPos = pos
		pos = SkipSpaces(text, len, pos)
		
		String name
		sscanf text[pos,len-1], "%s", name
		
		// HR, 2019-06-03: Handle names containing a single space.
		// Some SPEC files have labels that include spaces, such as "Two Theta".
		// This code handles that situation. Only one space is allowed as more than
		// one space is taken to be a label separator. spec_man.pdf says:
		// "each name separated from the other by two spaces".
		if (origPos > 0)
			Variable nameLen = strlen(name)
			Variable nameEndPos = pos + nameLen
			if (nameEndPos < len)
				if (CmpStr(text[nameEndPos]," ") == 0)
					if (CmpStr(text[nameEndPos+1]," ") != 0)
						String nameSecondPart
						sscanf text[nameEndPos+1,len-1], "%s", nameSecondPart
						name += "_" + nameSecondPart
					endif
				endif		
			endif
		endif
		
		if (origPos == 0)
			if (CmpStr(name,"#L") != 0)
				Print "Error in GetSPECSectionNameList - \"#L\" not found"
				return ""
			endif
			pos += strlen(name)
			continue
		endif
		
		name = CleanupName(name, 0)
		
		// This converts, e.g., Time into Time0. Time is a built-in function and is not allowed for wave names.
		Variable tmp = Exists(name)
		if (tmp!=0 && tmp!=1)
			name = UniqueName(name, 1, 0)
		endif
		
		// This deals with the fact that two columns may have the name, such as "Seconds"
		String origName = name
		int suffixNum = 0
		do
			if (strsearch(list,name,0) < 0)
				break
			endif
			suffixNum += 1
			sprintf name, "%s%d", origName, suffixNum	// Try <name>1, <name>2, ...
		while(1)
		
		list += name + ";"
		numNames += 1
		
		pos += strlen(name)
	while(pos < len)

	return list
End

static Function CreateSPECWaves(nameList, dataNumLines, outputWaves)
	String nameList
	Variable dataNumLines
	WAVE/WAVE& outputWaves			// Output: Free wave containing list of output waves
	
	int numItems = ItemsInList(nameList, ";")
	
	WAVE outputWaves = NewFreeWave(0x200, numItems)	// Create wave reference wave
	
	int i
	for(i=0; i<numItems; i+=1)
		String name = StringFromList(i, nameList)
		Make/O/D/N=(dataNumLines) $name
		WAVE w = $name
		outputWaves[i] = w
	endfor
	
	return 0
End

static Function StoreData(lineText, outputWaves, waveRow)
	String lineText				// A line of text containing numbers to be stored in the waves
	WAVE/WAVE outputWaves		// Wave reference wave containing list of output waves
	int waveRow					// Wave row in which to store data
	
	int numColumns = numpnts(outputWaves)
	int column
	for(column=0; column<numColumns; column+=1)
		String text = StringFromList(column, lineText, " ")	// Space-separated
		double value = str2num(text)
		WAVE w = outputWaves[column]
		w[waveRow] = value
	endfor	
End

static Function RedimensionWaves(outputWaves, numDataPointsLoaded)
	WAVE/WAVE outputWaves		// Wave reference wave containing list of output waves
	int numDataPointsLoaded
	
	int numColumns = numpnts(outputWaves)
	int column
	for(column=0; column<numColumns; column+=1)
		WAVE w = outputWaves[column]
		Redimension/N=(numDataPointsLoaded) w
	endfor	
End

// LoadSPECData(refNum, dataStartLine, dataNumLines, outputWaves)
//	Assumes that the file position is at the start of the data block.
// This is achieved because LoadSPECHeader reads all header lines.
static Function LoadSPECData(refNum, dataStartLine, dataNumLines, outputWaves)
	Variable refNum					// File reference number from Open command
	Variable dataStartLine
	Variable dataNumLines			// If NaN, the block has no data
	WAVE/WAVE outputWaves			// Wave reference wave containing list of output waves
	
	int numDataPointsLoaded = 0
	int dataEndLine = dataStartLine + dataNumLines - 1
	int lineNumber
	for(lineNumber=dataStartLine; lineNumber<=dataEndLine; lineNumber+=1)
		String lineText
		FReadLine refNum, lineText
		if (CmpStr(lineText[0],"#") == 0)
			continue							// This is a comment line
		endif
		StoreData(lineText, outputWaves, numDataPointsLoaded)
		numDataPointsLoaded += 1
	endfor
	
	if (numDataPointsLoaded < dataNumLines)	// Happens if there are comment lines in data block
		RedimensionWaves(outputWaves, numDataPointsLoaded)
	endif
	
	return 0
End

static Function LoadSPECSection(pathName, filePath, refNum, sectionNumber, sectionStartFPos, sectionStartLine, columnNamesFPos, dataStartLine, dataNumLines) 
	String pathName				// Name of an Igor symbolic path or ""
	String filePath					// Name of file or partial path relative to symbolic path or full path to file
	Variable refNum					// File reference number from Open command
	Variable sectionNumber
	Variable sectionStartFPos
	Variable sectionStartLine
	Variable columnNamesFPos
	Variable dataStartLine
	Variable dataNumLines
	
	// Each section is loaded into a separate data folder
	String dfName = "Scan" + num2istr(sectionNumber+1)	// HR, 2019-06-03: Use Scan1,Scan2,... instead of Section0,Section1,...
	NewDataFolder /O /S $dfName
	
	Variable result = LoadSPECHeader(refNum, sectionStartFPos, sectionStartLine)
	if (result != 0)
		SetDataFolder ::				// Reset current data folder to original
		return result
	endif
	// The file position is now at the start of the data block
	
	String nameList = GetSPECSectionNameList(refNum, columnNamesFPos)
	
	WAVE/WAVE/Z outputWaves			// Set to a free wave by CreateSPECWaves
	result = CreateSPECWaves(nameList, dataNumLines, outputWaves)
	if (result != 0)
		SetDataFolder ::				// Reset current data folder to original
		return result
	endif
	
	if (dataNumLines == 0)			// A block can have no data
		SetDataFolder ::				// Reset current data folder to original
		return 0
	endif
	
	// HR, 2019-06-03: Changed from LoadWave to homebrew to support comment lines in data blocks.
	result = LoadSPECData(refNum, dataStartLine, dataNumLines, outputWaves)
	
	SetDataFolder ::					// Reset current data folder to original
	
	return 0
End

static Function/S FileNameToDFName(filePath)
	String filePath

	String fileName = ParseFilePath(3, filePath, ":", 0, 0)
	String dfName = CleanupName(fileName, 0)		// Convert to standard Igor name for easier programming
	return dfName	
End

// LoadSPECFile(pathName, filePath, tableMode, graphMode, appendNewLeftAxis)
// Loads SPEC data and header information from .txt files.
// If pathName or filePath is "", an Open File dialog is displayed.
// Creates a main data folder based on the file name.
// Each section of the file is loaded into a separate data folder in the main data folder.
// For example if your file is named "MyFile" and contains 3 sections and you call this while
// the current data folder is root:, you get the following hierarchy:
//	root:
//		MyFile
//			Section0
//			Section1
//			Section2
// The data and header information for a given section is loaded into the corresponding
// section data folder.
// If a data folder already exists, conflicting waves and variables are overwritten.
Function LoadSPECFile(pathName, filePath)
	String pathName				// Name of an Igor symbolic path or ""
	String filePath					// Name of file or partial path relative to symbolic path or full path to file

	Variable refNum = 0

	// First get a valid reference to a file.
	if ((strlen(pathName)==0) || (strlen(filePath)==0))
		// Display dialog looking for file.
		String fileFilters = "SPEC Files (*.txt):.txt;"
		fileFilters += "All Files:.*;"
		Open/D/R/F=fileFilters/P=$pathName refNum as filePath
		filePath = S_fileName					// S_fileName is set by Open/D
		if (strlen(filePath) == 0)					// User cancelled?
			return -1
		endif
	endif

	// Open the file for reading
	Open /R /P=$pathName refNum as filePath
	if (refNum == 0)
		return -1								// Error opening file
	endif
	
	Wave/Z catalog = MakeSPECCatalog(refNum)
	if (!WaveExists(catalog))
		Print "Error in MakeSPECCatalog"
		Close refNum
		return -1
	endif
	
	// Make a data folder for the file
	String dfName = FileNameToDFName(filePath)
	NewDataFolder /O /S $dfName
	
	Variable numSections = DimSize(catalog,0)
	Variable sectionNumber
	Variable sectionsLoaded = 0
	for(sectionNumber = 0; sectionNumber<numSections; sectionNumber+=1)
		Variable sectionStartFPos = catalog[sectionNumber][%SectionStartFPos]
		Variable sectionStartLine = catalog[sectionNumber][%SectionStartLine]
		Variable columnNamesFPos = catalog[sectionNumber][%ColumnNamesFPos]
		Variable columnNamesLine = catalog[sectionNumber][%ColumnNamesLine]
		Variable dataStartLine = catalog[sectionNumber][%DataStartLine]
		Variable dataEndLine = catalog[sectionNumber][%DataEndLine]		// If NaN, the block has no data
		Variable dataNumLines = dataEndLine - dataStartLine + 1			// If NaN, the block has no data
		
		// A section may contain no data because it was aborted after 0 points.
		// When this happens, dataEndLine and dataNumLines are NaN. 
		Variable sectionHasNoData = NumType(dataNumLines)==2	// HR, 2019-06-03: Support block with no data
		if (sectionHasNoData)
			dataNumLines = 0
		endif
		
		Variable result = LoadSPECSection(pathName, filePath, refNum, sectionNumber, sectionStartFPos, sectionStartLine, columnNamesFPos, dataStartLine, dataNumLines) 
		if (result != 0)
			Printf "Error loading section %d\r", sectionNumber
			break
		endif
		sectionsLoaded += 1
	endfor
	
	SetDataFolder ::				// Reset current data folder to original

	Close refNum
	
	Printf "Created data folder %s containing %d sections from \"%s\"\r", dfName, sectionsLoaded, filePath
	
	return 0
End
