#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.
Menu  "load waves"
      "Load BSRF SPEC File",loadbsrfspecfile("", "")
End

static Function SkipbsrfSpaces(text, len, pos)
	String text
	Variable len
	Variable pos
	
	Variable ii
	for(ii=0; ii<len; ii+=1)
		if (CmpStr(text[pos]," ") != 0)
			break
		else
			pos += 1
		endif
	endfor
	return pos
End

static Function/S FileNameToDFName(fname1)
	String fname1

	String fileName = ParseFilePath(3, fname1, ":", 0, 0)
	String dfName = CleanupName(fileName, 0)
	return dfName	
End

function loadbsrfspecfile(path1,fname1)
    string path1,fname1
    variable a=0,i,j,k
    string str,fword
    variable pos,scanNumber=0
    if ((strlen(path1)==0) || (strlen(fname1)==0))
		// Display dialog looking for file.
		String fileFilters =  "All Files:.*;"
		Open/D/R/F=fileFilters/P=$path1 a as fname1
		fname1 = S_fileName					
		if (strlen(fname1) == 0)					
			return -1
		endif
	 endif
    Open/R/p=$path1 a as fname1
    String dfName = FileNameToDFName(fname1)
	 NewDataFolder /S $dfName
    do
	 FReadLine a, str
	 if(cmpstr(str[0,1],"#S")==0)
	     scanNumber+=1
	     newdatafolder/s $"scan"+num2str(scanNumber)
	 endif
	 i=0;j=0;pos=0
	 if(cmpstr(str[0,1],"#L")==0)
	     variable signal=100
	     make/o/n=0/t name
	     variable len=strlen(str)
	     do
	         pos=SkipbsrfSpaces(str, len, pos)
	         sscanf str[pos,len-1], "%s", fword
	         if(cmpstr(fword,"#L")==0)
	             pos+=strlen(fword)
	             continue
	         endif
	         
	         if ((CmpStr(fword,"Theta") == 0)&&(signal==1))
			       pos+=strlen(fword)
			       signal=0	
			       continue
		      endif
		      
		      if (CmpStr(fword,"Two") == 0) 
		           signal=1
		      endif		
	         
	         insertpoints i,1,name
	         if (CmpStr(fword,"Two") == 0) 
                name[i]=fword+"_Theta"
	         else
	             name[i]=fword
	         endif
	         i+=1
	         pos+=strlen(fword)
	         if(pos==len-1)
	             break
	         endif
	     while(pos<len)
	     make/d/o/n=(0,i) temp
	     do
	         FReadLine a, str
	         Variable dummy
			   sscanf str, "%g", dummy
				if (V_flag == 0)
				    if(stringmatch(str,"*Scan aborted*")==1)
				        continue
				    elseif(stringmatch(str,"*Scan resumed*")==1)
				        continue
				    else
				        break
				    endif
				endif
	         insertpoints/m=0 j,1,temp    
	         for(k=0;k<i;k++)
	             fword=stringfromlist(k,str," ") 
	             temp[j][k]=str2num(fword)
	         endfor
	         j+=1 
	     while(1)
	     for(k=0;k<i;k++)
	         duplicate/r=[0,j-1][k,k] temp  $name[k]
	     endfor
	     killwaves temp,name
	     setdatafolder ::
	 endif
	 while(strlen(str)!=0)
	 setdatafolder ::
	 close a
end
