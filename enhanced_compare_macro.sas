/******************************************************************************************
*  PROGRAM:    enhanced_compare_macro.sas
*  PURPOSE:    To perform a structured, flexible, and visually-rich comparison 
*              between two SAS datasets, highlighting variable-level differences 
*              with optional numeric tolerance and detailed HTML reporting.
*
*  EXECUTIVE SUMMARY:
*  ---------------------------------------------------------------------------------------
*  This macro compares two datasets on a variable-by-variable basis and generates an 
*  HTML report that:
*    - Shows overall dataset-level match summary
*    - Highlights variable match percentages with color-coded visuals
*    - Identifies variables exclusive to each dataset
*    - Displays a dedicated section for partially or fully mismatched variables
*    - Previews up to 10 mismatched rows per variable for quick inspection
*    - Supports numeric comparison tolerance for flexible matching
*
*  TECHNICAL SUMMARY:
*  ---------------------------------------------------------------------------------------
*  Key Features:
*    • Variable metadata extraction via PROC CONTENTS
*    • Row alignment using `_rownum` (no BY key needed)
*    • Macro loop over common variables with dynamic logic for:
*        - Missing handling
*        - Numeric tolerance (set via `%let tolerance = 0.01;`)
*        - Mismatch detection and summary statistics
*    • Conditional formatting on `Match_Pct` (Red/Yellow/Green)
*    • Modular tables:
*        - Overall match metrics
*        - Variable-level comparison summary
*        - Failing variables list
*        - Row-level mismatch samples (up to 10 per variable)
*
*  PARAMETERS:
*    • base=        → Name of base dataset
*    • compare=     → Name of comparison dataset
*    • tolerance=   → (Global macro var) Numeric difference threshold (default 0.01)
*
*  OUTPUT:
*    • HTML report saved at: /home/<user>/.../compare_report.html
*
*  AUTHOR:     Sagar Mandal
*  CREATED:    %sysfunc(today(), worddate.)
*  VERSION:    1.0
******************************************************************************************/

%macro compare_datasets(base=, compare=);
	/*
	TOLERANCE GUIDE:
	The macro uses the 'tolerance' value to compare numeric variables.
	This helps account for rounding differences or small calculation drift.
	
	Recommended Tolerance Ranges:
	- 0.01 → Use for strict comparisons (e.g., currency, integers)
	- 0.05 → Slight flexibility for rounded decimals
	- 0.10 → Moderate flexibility (good for survey scores, grades)
	- >0.10 → Use only when approximate matches are acceptable (e.g., metrics with known variability)
	
	Set tolerance based on the expected precision of your data.
	Example: %let tolerance = 0.05;
	*/

%let tolerance = 0.01;
	%put >>> Starting Dataset Comparison: &base vs &compare;

	/* Extract variable metadata */
	proc contents data=&base out=base_vars(keep=name type) noprint;
	run;

	proc contents data=&compare out=compare_vars(keep=name type) noprint;
	run;

	proc sql;
		create table base_only as select name from base_vars where name not 
			in (select name from compare_vars);
		create table compare_only as select name from compare_vars where name not 
			in (select name from base_vars);
		create table common_vars as select a.name, a.type from base_vars a inner join 
			compare_vars b on a.name=b.name and a.type=b.type;
	quit;

	/* Store common variables in macro vars */
	data _null_;
		set common_vars end=last;
		call symputx(cats('var', _n_), name);
		call symputx(cats('type', _n_), type);

		if last then
			call symputx('total_vars', _n_);
	run;

	%put >>> Found &total_vars common variables to compare;

	/* Tag rows with row number for alignment */
	data base_sorted;
		set &base;
		_rownum=_N_;
	run;

	data compare_sorted;
		set &compare;
		_rownum=_N_;
	run;

	data comp_summary;
		length Variable $32 Type $10 Match_Count Mismatch_Count Total_Obs 8 Match_Pct 
			8;
	run;

	%let total_match = 0;
	%let total_obs = 0;

	%do i=1 %to &total_vars;
		%let var = &&var&i;
		%let vtype = &&type&i;
		%put >>> Comparing variable: &var;

		data comp_&var;
			merge base_sorted(in=a keep=_rownum &var rename=(&var=base_&var)) 
				compare_sorted(in=b keep=_rownum &var rename=(&var=comp_&var));
			by _rownum;
			length result $10;

			if missing(base_&var) and missing(comp_&var) then
				result='Match';
			else if &vtype=1 then
				do;

					/* Numeric comparison */
					if abs(base_&var - comp_&var) <=&tolerance then
						result='Match';
					else
						result='Mismatch';
				end;
			else if base_&var=comp_&var then
				result='Match';

			/* Character comparison */
			else
				result='Mismatch';
		run;

		data mismatch_sample_&var;
			set comp_&var;
			where result="Mismatch";
			keep _rownum base_&var comp_&var result;

			if _N_ <=10;
		run;

		proc sql noprint;
			select count(*) into :_total from comp_&var;
			select count(*) into :_match from comp_&var where result='Match';
		quit;

		%let _mismatch = %eval(&_total - &_match);

		data _null_;
			if &_total=0 then
				call symputx('_pct', .);
			else
				call symputx('_pct', put(&_match / &_total * 100, 6.2));
		run;

		data comp_summary;
			set comp_summary;
			Variable="&var";
			Type="%sysfunc(ifc(&vtype=1, Numeric, Character))";
			Match_Count=&_match;
			Mismatch_Count=&_mismatch;
			Total_Obs=&_total;
			Match_Pct=&_pct;
			output;
		run;

		%let total_match = %eval(&total_match + &_match);
		%let total_obs = %eval(&total_obs + &_total);
	%end;
	%let overall_match_pct = %sysevalf(&total_match / &total_obs * 100);
	%put >>> TOTAL MATCHED OBS: &total_match;
	%put >>> TOTAL OBS COMPARED: &total_obs;
	%put >>> OVERALL MATCH %: &overall_match_pct;

	data comp_summary;
		set comp_summary;
		label Variable="Variable" Type="Data Type" Match_Count="Matching Rows" 
			Mismatch_Count="Mismatching Rows" Total_Obs="Total Observations" 
			Match_Pct="Match %";
	run;

	data failing_vars;
		set comp_summary;

		if Match_Pct < 100;
	run;

	data overall_summary;
		length Metric $40 Value $20;
		Metric="Total Variables Compared";
		Value=strip(put(&total_vars, 8.));
		output;
		Metric="Total Observations Compared";
		Value=strip(put(&total_obs, 8.));
		output;
		Metric="Overall Match %";
		Value=strip(put(&overall_match_pct, 6.2));
		output;
	run;

	title "📈 Overall Dataset Match Summary";

	proc print data=overall_summary noobs label style(header)={background=#003366 
			foreground=white font_weight=bold};
		label Metric="Metric" Value="Value";
	run;

	ods html file="/home/u63705630/ESQ1M6/Excel_sheets/compare_report.html" 
		style=statistical;
	title "📊 Dataset Comparison Summary (&base vs &compare)";

	proc report data=comp_summary nowd style(header)={background=#324376 
			foreground=white font_weight=bold};
		column Variable Type Match_Count Mismatch_Count Total_Obs Match_Pct;
		define Variable / display;
		define Type / display;
		define Match_Count / display;
		define Mismatch_Count / display;
		define Total_Obs / display;
		define Match_Pct / display;
		compute Match_Pct;

			if Match_Pct < 60 then
				call define(_col_, 'style', 'style={background=#FFCCCC}');
			else if Match_Pct < 90 then
				call define(_col_, 'style', 'style={background=#FFF2CC}');
			else if Match_Pct >=90 then
				call define(_col_, 'style', 'style={background=#D9EAD3}');
		endcomp;
	run;

	title "❌ Variables with Less Than 100% Match";

	proc print data=failing_vars noobs label style(header)={background=#8B0000 
			foreground=white font_weight=bold} style(data)={background=#FFF5F5};
		label Variable="Variable" Type="Data Type" Match_Count="Matching Rows" 
			Mismatch_Count="Mismatching Rows" Total_Obs="Total Observations" 
			Match_Pct="Match %";
	run;

%do i = 1 %to &total_vars;
    %let var = &&var&i;

    proc sql noprint;
        select count(*) into :_has_mismatch from mismatch_sample_&var;
    quit;

    %if &_has_mismatch > 0 %then %do;
        title "🔍 Top Mismatches for Variable: &var";

        proc print data=mismatch_sample_&var noobs 
            label 
            style(header)={background=#444444 foreground=white font_weight=bold}
            style(data)={background=#FFFDFD};
            label 
                _rownum = "Row #"
                base_&var = "Base Value"
                comp_&var = "Compare Value"
                result = "Result";
        run;
    %end;
%end;


	title "🧾 Unique Variables Report";

	proc print data=base_only label noobs;
		title2 "Variables present only in &base";
	run;

	proc print data=compare_only label noobs;
		title2 "Variables present only in &compare";
	run;

	ods html close;
	%put >>> Report Generated: compare_report.html;
%mend compare_datasets;

%compare_datasets(base=work.dataset1, compare=work.dataset2);
