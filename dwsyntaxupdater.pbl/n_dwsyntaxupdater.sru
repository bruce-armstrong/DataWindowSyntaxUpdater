//objectcomments Converts DataWindow source (.srd) files to the syntax of the current DataWindow release
forward
global type n_dwsyntaxupdater from nonvisualobject
end type
type os_filedatetime from structure within n_dwsyntaxupdater
end type
type os_finddata from structure within n_dwsyntaxupdater
end type
end forward

type os_filedatetime from structure
	unsignedlong		ul_lowdatetime
	unsignedlong		ul_highdatetime
end type

type os_finddata from structure
	unsignedlong		ul_fileattributes
	os_filedatetime		str_creationtime
	os_filedatetime		str_lastaccesstime
	os_filedatetime		str_lastwritetime
	unsignedlong		ul_filesizehigh
	unsignedlong		ul_filesizelow
	unsignedlong		ul_reserved0
	unsignedlong		ul_reserved1
	character		ch_filename[260]
	character		ch_alternatefilename[14]
end type

global type n_dwsyntaxupdater from nonvisualobject
end type
global n_dwsyntaxupdater n_dwsyntaxupdater

type prototypes
Function longptr FindFirstFileW (ref string filename, ref os_finddata findfiledata) library "KERNEL32.DLL"
Function boolean FindNextFileW (longptr handle, ref os_finddata findfiledata) library "KERNEL32.DLL"
Function boolean FindClose (longptr handle) library "KERNEL32.DLL"
end prototypes

type variables
constant string TITLE = "DataWindow Syntax Updater"
constant unsignedlong FILE_ATTRIBUTE_DIRECTORY = 16

// Options from the command line
string	is_sourcefolder
string	is_outputfolder
string	is_logfile
boolean	ib_dryrun
boolean	ib_force
boolean	ib_quiet

// Results
long		il_converted
long		il_current
long		il_failed
long		il_warnings
integer	ii_log = -1
end variables

forward prototypes
public function integer of_run (string as_commandline)
public function integer of_convert (string as_source, ref string as_result, ref string as_message, ref string as_warning)
protected function integer of_parsecommandline (string as_commandline)
protected function integer of_processfolder (string as_folder)
protected function integer of_processfile (string as_file)
protected function integer of_insertdata (ref string as_syntax, string as_data)
protected function string of_getrelease (string as_syntax)
protected function string of_replaceall (string as_text, string as_old, string as_new)
protected function integer of_readfile (string as_file, ref string as_text, ref encoding ae_encoding)
protected function integer of_writefile (string as_file, string as_text, encoding ae_encoding)
protected function integer of_createfolder (string as_folder)
protected function boolean of_isdirectory (unsignedlong aul_attributes)
protected function string of_usage ()
protected subroutine of_log (string as_message)
end prototypes

public function integer of_run (string as_commandline);// Converts every .srd file under the source folder named on the command line,
// or picked by the user when none is given, and writes a log of the results.
// Returns 1 when every file was handled, -1 when any file failed or the
// command line was not valid, and 0 when the user cancelled.
string	ls_summary

if of_parsecommandline(as_commandline) < 0 then
	if not ib_quiet then MessageBox(TITLE, of_usage(), Information!)
	return -1
end if

if is_sourcefolder = "" then
	if ib_quiet then return -1
	if GetFolder("Select the folder that holds the DataWindow source (.srd) files", is_sourcefolder) <> 1 then return 0
end if
if Right(is_sourcefolder, 1) = "\" then is_sourcefolder = Left(is_sourcefolder, Len(is_sourcefolder) - 1)
if Right(is_outputfolder, 1) = "\" then is_outputfolder = Left(is_outputfolder, Len(is_outputfolder) - 1)
if Lower(is_outputfolder) = Lower(is_sourcefolder) then is_outputfolder = ""

if not DirectoryExists(is_sourcefolder) then
	if not ib_quiet then MessageBox(TITLE, "The folder ~"" + is_sourcefolder + "~" does not exist.", StopSign!)
	return -1
end if

// Converted files written under the source folder would be picked up again by the scan
if is_outputfolder <> "" and Lower(Left(is_outputfolder, Len(is_sourcefolder) + 1)) = Lower(is_sourcefolder + "\") then
	if not ib_quiet then MessageBox(TITLE, "The output folder can't be inside the source folder.", StopSign!)
	return -1
end if

if is_logfile = "" then is_logfile = GetCurrentDirectory() + "\dwsyntaxupdater.log"
ii_log = FileOpen(is_logfile, LineMode!, Write!, LockWrite!, Replace!, EncodingUTF8!)
if ii_log < 0 then
	if not ib_quiet then MessageBox(TITLE, "Unable to create the log file ~"" + is_logfile + "~".", StopSign!)
	return -1
end if

of_log(TITLE + " - " + String(Now(), "yyyy-mm-dd hh:mm:ss"))
of_log("Source folder: " + is_sourcefolder)
if ib_dryrun then
	of_log("Dry run: no files are written")
elseif is_outputfolder <> "" then
	of_log("Output folder: " + is_outputfolder)
else
	of_log("Files are updated in place")
end if
if ib_force then of_log("Rewriting files that are already at the current release")
of_log("")

SetPointer(HourGlass!)
of_processfolder(is_sourcefolder)

ls_summary = String(il_converted) + " converted, " + String(il_current) + " already current, " + &
	String(il_failed) + " failed, " + String(il_warnings) + " with warnings"
of_log("")
of_log(ls_summary)
FileClose(ii_log)
ii_log = -1

if not ib_quiet then
	MessageBox(TITLE, ls_summary + ".~r~n~r~nDetails are in " + is_logfile, Information!)
end if

if il_failed > 0 then return -1
return 1
end function

public function integer of_convert (string as_source, ref string as_result, ref string as_message, ref string as_warning);// Loads DataWindow source into the DataWindow engine and asks the engine for the syntax
// back, which it writes at the current release, as the DataWindow painter does on save.
// Lines ahead of the release line (//objectcomments, $PBExportHeader$) are kept as they are.
// Returns 1 when the source was converted, 0 when it is already at the current release
// and -1 when it could not be converted (as_message says why).
long			ll_pos
string		ls_text, ls_prefix, ls_body, ls_new, ls_error, ls_eol
string		ls_oldrelease, ls_newrelease
datastore	lds_source, lds_check

as_result = ""
as_message = ""
as_warning = ""

ls_text = as_source
// Drop a byte order mark left in the text; writing the file adds one back for its encoding
if Asc(Left(ls_text, 1)) = 65279 then ls_text = Mid(ls_text, 2)

if Left(ls_text, 8) = "release " then
	ll_pos = 1
else
	ll_pos = Pos(ls_text, "~nrelease ")
	if ll_pos > 0 then ll_pos ++
end if
if ll_pos = 0 then
	as_message = "no release line; not DataWindow source"
	return -1
end if

ls_prefix = Left(ls_text, ll_pos - 1)
ls_body = Mid(ls_text, ll_pos)
ls_oldrelease = of_getrelease(ls_body)
if Pos(ls_body, "~r~n") > 0 then ls_eol = "~r~n" else ls_eol = "~n"

lds_source = create datastore
if lds_source.Create(ls_body, ls_error) <> 1 then
	destroy lds_source
	as_message = "the DataWindow engine rejected the source: " + ls_error
	return -1
end if

ls_new = lds_source.Describe("DataWindow.Syntax")
if ls_new = "" or ls_new = "!" or ls_new = "?" then
	destroy lds_source
	as_message = "the DataWindow engine returned no syntax"
	return -1
end if

ls_newrelease = of_getrelease(ls_new)
if ls_oldrelease = ls_newrelease and not ib_force then
	destroy lds_source
	as_message = "already release " + ls_oldrelease
	return 0
end if

// DataWindow.Syntax leaves out initial data, which the painter writes right after the table block
if lds_source.RowCount() > 0 then
	if of_insertdata(ls_new, lds_source.Describe("DataWindow.Syntax.Data")) < 0 then
		destroy lds_source
		as_message = "unable to place the initial data in the converted syntax"
		return -1
	end if
end if

// Check that the new syntax loads and describes the same objects and initial rows
lds_check = create datastore
if lds_check.Create(ls_new, ls_error) <> 1 then
	as_message = "the converted syntax does not load: " + ls_error
elseif lds_check.Describe("DataWindow.Objects") <> lds_source.Describe("DataWindow.Objects") then
	as_message = "the converted syntax describes different objects"
elseif lds_check.RowCount() <> lds_source.RowCount() then
	as_message = "the converted syntax lost initial data (" + String(lds_source.RowCount()) + &
		" rows before, " + String(lds_check.RowCount()) + " after)"
end if
destroy lds_check
destroy lds_source
if as_message <> "" then return -1

if Pos(ls_body, "~nreport(") > 0 then
	as_warning = "has nested reports; check them in the DataWindow painter"
end if

// Keep the file's line endings and whether it ends with a line break
ls_new = of_replaceall(ls_new, "~r~n", "~n")
if ls_eol = "~r~n" then ls_new = of_replaceall(ls_new, "~n", "~r~n")
if Right(ls_body, Len(ls_eol)) = ls_eol and Right(ls_new, Len(ls_eol)) <> ls_eol then ls_new += ls_eol

as_result = ls_prefix + ls_new
as_message = "release " + ls_oldrelease + " -> " + ls_newrelease
return 1
end function

protected function integer of_parsecommandline (string as_commandline);// Splits the command line into arguments (double quotes group spaces) and reads the options.
// Returns -1 for an unknown option, a second folder, or a request for help.
long		ll_pos, ll_len, ll_count, ll_sep
string	ls_char, ls_token, ls_args[], ls_name, ls_value
boolean	lb_quoted, lb_intoken

ll_len = Len(as_commandline)
for ll_pos = 1 to ll_len
	ls_char = Mid(as_commandline, ll_pos, 1)
	if ls_char = "~"" then
		lb_quoted = not lb_quoted
		lb_intoken = true
	elseif (ls_char = " " or ls_char = "~t") and not lb_quoted then
		if lb_intoken then
			ll_count ++
			ls_args[ll_count] = ls_token
			ls_token = ""
			lb_intoken = false
		end if
	else
		ls_token += ls_char
		lb_intoken = true
	end if
next
if lb_intoken then
	ll_count ++
	ls_args[ll_count] = ls_token
end if

for ll_pos = 1 to ll_count
	if Left(ls_args[ll_pos], 1) = "/" then
		// /name, /name=value or /name:value
		ls_name = Mid(ls_args[ll_pos], 2)
		ls_value = ""
		ll_sep = Pos(ls_name, "=")
		if ll_sep = 0 or (Pos(ls_name, ":") > 0 and Pos(ls_name, ":") < ll_sep) then ll_sep = Pos(ls_name, ":")
		if ll_sep > 0 then
			ls_value = Mid(ls_name, ll_sep + 1)
			ls_name = Left(ls_name, ll_sep - 1)
		end if

		choose case Lower(ls_name)
			case "out"
				if ls_value = "" then return -1
				is_outputfolder = ls_value
			case "log"
				if ls_value = "" then return -1
				is_logfile = ls_value
			case "dryrun"
				ib_dryrun = true
			case "force"
				ib_force = true
			case "quiet"
				ib_quiet = true
			case else
				return -1
		end choose
	else
		if is_sourcefolder <> "" then return -1
		is_sourcefolder = ls_args[ll_pos]
	end if
next

return 1
end function

protected function integer of_processfolder (string as_folder);// Converts the .srd files in a folder and its subfolders.
// Folders whose names start with a period (.git, .pb) are skipped.
longptr		ll_handle
string		ls_spec, ls_name
boolean		lb_found
os_finddata	lstr_finddata

ls_spec = as_folder + "\*"
ll_handle = FindFirstFileW(ls_spec, lstr_finddata)
if ll_handle = -1 then
	il_failed ++
	of_log("FAILED     " + as_folder + ": unable to read the folder")
	return -1
end if

do
	ls_name = String(lstr_finddata.ch_filename)
	if of_isdirectory(lstr_finddata.ul_fileattributes) then
		if Left(ls_name, 1) <> "." then of_processfolder(as_folder + "\" + ls_name)
	elseif Lower(Right(ls_name, 4)) = ".srd" then
		of_processfile(as_folder + "\" + ls_name)
	end if
	lb_found = FindNextFileW(ll_handle, lstr_finddata)
loop while lb_found

FindClose(ll_handle)
return 1
end function

protected function integer of_processfile (string as_file);// Converts one .srd file and writes it back in place, or to the same relative path
// under the output folder. Files already at the current release are not written.
integer	li_rc
string	ls_relative, ls_source, ls_result, ls_message, ls_warning, ls_target
encoding	le_encoding

ls_relative = Mid(as_file, Len(is_sourcefolder) + 2)

if of_readfile(as_file, ls_source, le_encoding) < 0 then
	il_failed ++
	of_log("FAILED     " + ls_relative + ": unable to read the file")
	return -1
end if

li_rc = of_convert(ls_source, ls_result, ls_message, ls_warning)
choose case li_rc
	case 0
		il_current ++
		of_log("CURRENT    " + ls_relative + ": " + ls_message)
		return 0
	case -1
		il_failed ++
		of_log("FAILED     " + ls_relative + ": " + ls_message)
		return -1
end choose

if not ib_dryrun then
	if is_outputfolder = "" then
		ls_target = as_file
	else
		ls_target = is_outputfolder + "\" + ls_relative
		of_createfolder(Left(ls_target, LastPos(ls_target, "\") - 1))
	end if

	if of_writefile(ls_target, ls_result, le_encoding) < 0 then
		il_failed ++
		of_log("FAILED     " + ls_relative + ": unable to write " + ls_target)
		return -1
	end if
end if

il_converted ++
of_log("CONVERTED  " + ls_relative + ": " + ls_message)
if ls_warning <> "" then
	il_warnings ++
	of_log("WARNING    " + ls_relative + ": " + ls_warning)
end if

return 1
end function

protected function integer of_insertdata (ref string as_syntax, string as_data);// Inserts a data(...) section on the line after the table(...) block of DataWindow syntax
long		ll_start, ll_end, ll_len, ll_depth
string	ls_char
boolean	lb_instring

if Left(Trim(as_data), 5) <> "data(" then return -1

if Left(as_syntax, 6) = "table(" then
	ll_start = 1
else
	ll_start = Pos(as_syntax, "~ntable(")
	if ll_start = 0 then return -1
	ll_start ++
end if

// Find the parenthesis that closes the table block; strings are in double quotes with ~ as the escape
ll_len = Len(as_syntax)
for ll_end = ll_start + 5 to ll_len
	ls_char = Mid(as_syntax, ll_end, 1)
	if lb_instring then
		if ls_char = "~~" then
			ll_end ++
		elseif ls_char = "~"" then
			lb_instring = false
		end if
	elseif ls_char = "~"" then
		lb_instring = true
	elseif ls_char = "(" then
		ll_depth ++
	elseif ls_char = ")" then
		ll_depth --
		if ll_depth = 0 then exit
	end if
next
if ll_end > ll_len then return -1

ll_end = Pos(as_syntax, "~n", ll_end)
if ll_end = 0 then
	as_syntax += "~r~n" + Trim(as_data) + "~r~n"
else
	as_syntax = Left(as_syntax, ll_end) + Trim(as_data) + "~r~n" + Mid(as_syntax, ll_end + 1)
end if

return 1
end function

protected function string of_getrelease (string as_syntax);// Returns the release number from the "release n;" line at the start of DataWindow syntax
long	ll_start, ll_end

ll_start = Pos(as_syntax, "release ")
if ll_start = 0 then return ""
ll_end = Pos(as_syntax, ";", ll_start)
if ll_end = 0 then return ""

return Trim(Mid(as_syntax, ll_start + 8, ll_end - ll_start - 8))
end function

protected function string of_replaceall (string as_text, string as_old, string as_new);// Replaces every occurrence of as_old in as_text with as_new
long	ll_pos

ll_pos = Pos(as_text, as_old)
do while ll_pos > 0
	as_text = Replace(as_text, ll_pos, Len(as_old), as_new)
	ll_pos = Pos(as_text, as_old, ll_pos + Len(as_new))
loop

return as_text
end function

protected function integer of_readfile (string as_file, ref string as_text, ref encoding ae_encoding);// Reads a whole file and reports its encoding, so it can be written back the same way
integer	li_file
long		ll_rc

ae_encoding = FileEncoding(as_file)
li_file = FileOpen(as_file, TextMode!, Read!, Shared!)
if li_file < 0 then return -1

as_text = ""
ll_rc = FileReadEx(li_file, as_text)
FileClose(li_file)

// -100 is end of file, which an empty file returns straight away
if ll_rc < 0 and ll_rc <> -100 then return -1
return 1
end function

protected function integer of_writefile (string as_file, string as_text, encoding ae_encoding);// Replaces a file with the given text in the given encoding
integer	li_file
long		ll_rc

li_file = FileOpen(as_file, TextMode!, Write!, LockWrite!, Replace!, ae_encoding)
if li_file < 0 then return -1

ll_rc = FileWriteEx(li_file, as_text)
FileClose(li_file)

if ll_rc < 0 then return -1
return 1
end function

protected function integer of_createfolder (string as_folder);// Creates a folder along with any of its parents that don't exist yet
long	ll_pos

if as_folder = "" or Right(as_folder, 1) = ":" then return 1
if DirectoryExists(as_folder) then return 1

ll_pos = LastPos(as_folder, "\")
if ll_pos > 0 then
	if of_createfolder(Left(as_folder, ll_pos - 1)) < 0 then return -1
end if

return CreateDirectory(as_folder)
end function

protected function boolean of_isdirectory (unsignedlong aul_attributes);// Tests the directory bit of a Win32 file attribute value
return Mod(Truncate(aul_attributes / FILE_ATTRIBUTE_DIRECTORY, 0), 2) = 1
end function

protected function string of_usage ();// Describes the command line
return "dwsyntaxupdater [folder] [/out=folder] [/log=file] [/dryrun] [/force] [/quiet]~r~n~r~n" + &
	"Converts every DataWindow source (.srd) file under the folder, and its subfolders, " + &
	"to the syntax of the current DataWindow release, the way saving it in the DataWindow painter does.~r~n~r~n" + &
	"folder~tThe folder to scan. When left out, you're asked for one.~r~n" + &
	"/out~tWrite converted files to this folder, keeping their relative paths, instead of replacing them.~r~n" + &
	"/log~tThe log file. Defaults to dwsyntaxupdater.log in the current folder.~r~n" + &
	"/dryrun~tReport what would be converted without writing any files.~r~n" + &
	"/force~tRewrite files that are already at the current release.~r~n" + &
	"/quiet~tShow no messages; results go to the log only."
end function

protected subroutine of_log (string as_message);// Writes a line to the log file
if ii_log >= 0 then FileWriteEx(ii_log, as_message)
end subroutine

on n_dwsyntaxupdater.create
call super::create
TriggerEvent( this, "constructor" )
end on

on n_dwsyntaxupdater.destroy
TriggerEvent( this, "destructor" )
call super::destroy
end on

