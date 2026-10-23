//objectcomments Brings DataWindow source files up to the current DataWindow release
forward
global type dwsyntaxupdater from application
end type
global transaction sqlca
global dynamicdescriptionarea sqlda
global dynamicstagingarea sqlsa
global error error
global message message
end forward

global type dwsyntaxupdater from application
string appname = "dwsyntaxupdater"
string appruntimeversion = "25.1.0.6430"
integer highdpimode = 0
end type
global dwsyntaxupdater dwsyntaxupdater

on dwsyntaxupdater.create
appname="dwsyntaxupdater"
message=create message
sqlca=create transaction
sqlda=create dynamicdescriptionarea
sqlsa=create dynamicstagingarea
error=create error
end on

on dwsyntaxupdater.destroy
destroy(sqlca)
destroy(sqlda)
destroy(sqlsa)
destroy(error)
destroy(message)
end on

event open;n_dwsyntaxupdater lnv_updater

lnv_updater = create n_dwsyntaxupdater
lnv_updater.of_run(commandline)
destroy lnv_updater
end event

