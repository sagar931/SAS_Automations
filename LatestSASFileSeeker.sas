%macro init_libs(parent_dir=);

  data dir_lib(drop=i rc did);
    length dir_names $256.;
    rc = filename('mydirs',"&parent_dir");
    did = dopen('mydirs');
    if did then do;
      dir_count = dnum(did);
      do i = 1 to dir_count;
        dir_names = dread(did, i);
        output;
      end;
    end;
    rc = dclose(did);
  run;


  proc sort data=dir_lib;
    by dir_names;
  run;


  data dir_lib;
    set dir_lib(where=(dir_names NE '%.%'));
    length libname $8.;
    libname = cats('Child', put(_N_, z2.));
  run;


  proc sql noprint;
    select count(*) into :dir_count from dir_lib;
  quit;


  %do i = 1 %to &dir_count;
    data _null_;
      set dir_lib (firstobs=&i obs=&i);
      call symput(cats('libname', put(&i, 8. -L)), libname);
      call symput(cats('dirname', put(&i, 8. -L)), dir_names);
    run;

    %let current_libname = &&libname&i;
    %let current_dirname = &&dirname&i;

    %if %sysfunc(fileexist(&parent_dir/&current_dirname)) %then %do;
      libname &current_libname "&parent_dir/&current_dirname";
    %end;
  %end;
  
  
/* ######################################################################################################   */
%MACRO LO_DATA;

PROC SQL noprint;
select DISTINCT(dir_names) into: dname separated by ' ' from dir_lib;
QUIT;

%LET COUNT=%SYSFUNC(COUNTW("&dname",' '));

%DO i=1 %TO &COUNT.;

%LET value = %SCAN(&dname,&i,' ');
%let dir = &parent_dir/&value;
%let fType = sas7bdat;

data all_fn_&value (drop=_:);
	_rc=filename("dRef", "&dir.");
	_id=dopen("dRef");
	_n=dnum(_id);

	do _i=1 to _n;
		name=dread(_id, _i);

		if upcase(scan(name, -1, "."))=upcase("&fType.") then
			do;
				_rc=filename("fRef", "&dir./" || strip(name));
				_fid=fopen("fRef");
				size=finfo(_fid, "File Size (bytes)")/1000;
				dateCreate=finfo(_fid, "Create Time");
				dateModify=finfo(_fid, "Last Modified");
				_rc=fclose(_fid);
				output;
			end;
	end;
	_rc=dclose(_id);
run;

data all_fn1_&value;
format today_date file_date Date9. 
       today_time file_time time.;
set all_fn_&value(keep=name dateModify);
file_date=input(dateModify,DATE9.);
file_time=hms(substr(dateModify,11,2),substr(dateModify,14,2),substr(dateModify,17,2));
today_date=today();
today_time=time();
Diff_dt=INTCK('Day',file_date,today_date);
Diff_Hr=INTCK('Hour',file_time,today_time);
Diff_MM=INTCK('Minute',file_time,today_time);
Diff_SS=INTCK('Second',file_time,today_time);
drop dateModify;
dir_name = symget('value');
run;

proc sql;
create table latest_data_&value as 
select name,dir_name from all_fn1_&value 
where Diff_dt in (select MIN(Diff_dt) from all_fn1_&value) and
      Diff_Hr in (select MIN(Diff_Hr) from all_fn1_&value) and
      Diff_MM in (select MIN(Diff_MM) from all_fn1_&value) and
      Diff_SS in (select MIN(Diff_SS) from all_fn1_&value) ;
quit;
%END;

Data latest_data;
set latest_data_:;
run;

%mend LO_DATA;
%LO_DATA;

PROC SQL;
Create table USER_REQ as 
select x.dir_names, x.libname, y.name from dir_lib as x 
left join latest_data as y 
on x.dir_names = y.dir_name;
QUIT;

/* ######################################################################################################   */

%mend init_libs;

/* Example of usage */
%init_libs(parent_dir=/home/u63705630/game);
