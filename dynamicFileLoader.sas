/* 
Executive Summary: This code is designed to import all files in a given directory, supporting various extensions 
                   including CSV and XLSX files with multiple sheets. The code processes and imports files, creating 
                   corresponding SAS datasets.


Developer Name: Sagar Mandal
LinkedIn Profile: https://www.linkedin.com/in/sagar-mandal-526698196/
Date Created: 29JUL2024

Code Execution: To use the code, simply add the directory path in the macro variable 'dir' located at line number 29. 
                The code creates a dataset named 'ALL_FILES', which will contain the names of all files in the specified 
                directory and proceed with the processing. Each created dataset will have the same name as the file 
                (in capital letters) with punctuation removed. Additionally, two new variables, 'DCODE' and 'fileType',
                will be included in the created SAS dataset. 'DCODE' is a unique identifier for backtracking, and 
                'fileType' contains the file extension.

                 For XLSX files, the code extracts all sheet names and imports them, creating datasets with sheet numbers
                 appended to the file name. For instance, if the file name is 'P1OFFICESUPPLY.xlsx' and it contains 4 
                 sheets, the code will create datasets named 'P1OFFICESUPPLY_S1', 'P1OFFICESUPPLY_S2', and so on. 
                 Each dataset will include a variable 'sheetName' containing the actual sheet name from the XLSX file.

Supported Extensions: XLS, XLSX, CSV, JMP, DBF, TAB, SAV, DTA

Note: If your file is comma-separated but has a '.txt' extension, Change it to '.csv'.
*/

/* Change path */
%let dir = /home/u63705630/ANY_FILE/FILES;


data all_files (drop=_:);
    _rc = filename("dRef", "&dir.");
    if _rc then do;
        put "ERROR: Unable to assign fileref to the directory.";
        stop;
    end;

    _id = dopen("dRef");
    if _id = 0 then do;
        put "ERROR: Unable to open directory.";
        stop;
    end;

    _n = dnum(_id);
    do _i = 1 to _n;
        orignalName = dread(_id, _i);
        ext = UPCASE(scan(orignalName, -1, '.'));
        _rc = filename("fRef", "&dir./" || strip(orignalName));
        _fid = fopen("fRef");

        if _fid = 0 then do;
            put "ERROR: Unable to open file " orignalName;
            continue;
        end;

        size = finfo(_fid, "File Size (bytes)") / 1000;
        dateCreate = finfo(_fid, "Create Time");
        dateModify = finfo(_fid, "Last Modified");
        datasetName = UPCASE(COMPRESS(COMPRESS(orignalName, "." || scan(orignalName, -1, '.')), , 'p'));
        DCODE = CATX("_", "DATASET", _i);
        _rc = fclose(_fid);

        if UPCASE(ext) = "TXT" then ext = "TAB";
        output;
    end;

    _rc = dclose(_id);
run;

proc sql;
	select orignalName into: oList separated by "," from all_files;
	select datasetName into: dataList separated by " " from all_files;
	select ext into: extlist separated by " " from all_files;
	select Distinct(ext) into: unqext separated by " " from all_files;
	select DCODE into: DCODE separated by " " from all_files;
quit;

%put value of olist &oList;
%put value of ext2 is &unqext;
%let COUNTF= %SYSFUNC(COUNTW("&dataList" , ' '));
%let nUnqExt= %SYSFUNC(COUNTW("&unqext" , ' '));
%put value of dataList is &dataList.;

%macro dataImport();
	options NOSYMBOLGEN;

	%do i=1 %to &COUNTF;
		%let orignalFname = %SCAN("&oList", &i, ",");
		%let datasetName = %SCAN("&dataList", &i, " ");
		%let extension = %SCAN("&extlist", &i, " ");
		%let dcodeValue = %SCAN("&DCODE", &i, " ");

		%do j=1 %to &nUnqExt;
			%let unqExtVal = %upcase(%SCAN("&unqext", &j, " "));

			%if %upcase("&extension")="&unqExtVal" and %upcase("&extension") NE "XLSX" 
				%then
					%do;
					%Put Common values found and value of I is &i;

					proc import datafile="&dir/&orignalFname" 
							DBMS=&unqExtVal. out=&datasetName. REPLACE;
					RUN;

					Data &datasetName.;
						set &datasetName.;
						DCODE=symget('dcodeValue');
						fileType=symget('extension');
					run;

				%end;
		%end;

		/* for &nUnqExt */


		
		%if %upcase("&extension")="XLSX" %then
			%do;
				%put found xlsx;
				libname myxlsx xlsx "&dir/&orignalFname";

				proc sql;
					select count(memname) into: sheetCount from sashelp.vtable where 
						libname='MYXLSX';
					select memname into: sheetlist Separated By "," from sashelp.vtable where 
						libname='MYXLSX';
				quit;

				%do k=1 %to &sheetCount;
					%let sheetName = %SCAN("&sheetlist", &k, ",");

					proc import datafile="&dir/&orignalFname" Out=&datasetName._S&k DBMS=XLSX 
							REPLACE;
						SHEET="&sheetName";
						GETNAMES=YES;
					run;

					Data &&datasetName._S&k;
						set &datasetName._S&k;
						DCODE=symget('dcodeValue');
						fileType=symget('extension');
						sheetName=symget('sheetName');
						run;
					%end;
				%end;
		%end;

		/* for &COUNTIF */
%mend;

	%dataImport;
