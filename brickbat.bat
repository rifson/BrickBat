@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================================
rem  BrickBat - a menu for the Databricks CLI in the Windows terminal
rem
rem  * Front page with the login status of every profile
rem  * Log in, log out, switch or add a profile
rem  * Secret scopes: list, search, favourites, compare across environments,
rem    edit secrets and manage access
rem
rem  Needs Windows 10 or 11. Double-click it or run it from a terminal - it
rem  works from any folder, and offers to install the Databricks CLI if missing.
rem  Set NO_COLOR=1 in Windows if you want it without colours.
rem
rem  Unofficial - not affiliated with or endorsed by Databricks, Inc.
rem  MIT licence, see LICENSE.
rem ============================================================================
set "BB_VERSION=1.1.0"

rem ---- settings ----------------------------------------------------------------
rem  SYNC_CLI_DEFAULT=1 : switching profile here also runs databricks auth switch,
rem                       so plain databricks commands in every terminal follow it
rem  SYNC_CLI_DEFAULT=0 : BrickBat remembers its own profile, CLI default untouched
set "SYNC_CLI_DEFAULT=1"
rem  LOOKUP_LIMIT : looking inside scopes - for a key or for someone's access -
rem                 costs one call per scope, so it is only offered once a list
rem                 shows this many scopes or fewer. Capped at 50.
set "LOOKUP_LIMIT=20"
if !LOOKUP_LIMIT! gtr 50 set "LOOKUP_LIMIT=50"
if !LOOKUP_LIMIT! lss 1 set "LOOKUP_LIMIT=1"
rem  ENV_WORDS : words that mark the environment inside scope names, like the dev
rem              in analytics.dev.secrets or analytics_dev. To find a scope in the
rem              other environments, that word is swapped for each of these.
set "ENV_WORDS=dev test tst qa uat stg stage staging preprod prod prd"

rem ---- the workspace comes from the profile only -------------------------------
rem  BrickBat picks the workspace with -p. The CLI lets DATABRICKS_HOST, DATABRICKS_TOKEN
rem  and the like set in Windows win over -p, so changes would go to that workspace
rem  instead of the one shown. They are cleared for this window only.
set "ENV_AUTH="
for %%v in (HOST TOKEN AUTH_TYPE CLIENT_ID CLIENT_SECRET ACCOUNT_ID WORKSPACE_ID EXPERIMENTAL_IS_UNIFIED_HOST AZURE_RESOURCE_ID USERNAME PASSWORD) do if defined DATABRICKS_%%v (
  set "ENV_AUTH=!ENV_AUTH! DATABRICKS_%%v"
  set "DATABRICKS_%%v="
)

rem ---- console: UTF-8 for the banner and the CLI output, ANSI colours ----------
set "ORIG_CP="
for /f "tokens=2 delims=:." %%c in ('chcp') do set "ORIG_CP=%%c"
if defined ORIG_CP set "ORIG_CP=!ORIG_CP: =!"
chcp 65001 >nul
title BrickBat

for %%v in (c0 cB1 cB2 cB3 cB4 cB5 cB6 cBrand cHead cDim cKey cOk cErr cWarn) do set "%%v="
set "ESC="
if not defined NO_COLOR for /f %%e in ('echo prompt $E ^| cmd') do set "ESC=%%e"
if defined ESC (
  set "c0=!ESC![0m"
  set "cB1=!ESC![38;2;255;128;88m"
  set "cB2=!ESC![38;2;255;104;68m"
  set "cB3=!ESC![38;2;255;80;50m"
  set "cB4=!ESC![38;2;255;54;33m"
  set "cB5=!ESC![38;2;222;44;28m"
  set "cB6=!ESC![38;2;150;36;24m"
  set "cBrand=!ESC![38;2;255;54;33m"
  set "cHead=!ESC![1;97m"
  set "cDim=!ESC![90m"
  set "cKey=!ESC![96m"
  set "cOk=!ESC![92m"
  set "cErr=!ESC![91m"
  set "cWarn=!ESC![93m"
)

rem ---- state and temp files ----------------------------------------------------
set "STATE_DIR=!LOCALAPPDATA!\brickbat"
if not exist "!STATE_DIR!\" mkdir "!STATE_DIR!" >nul 2>&1
set "STATE_FILE=!STATE_DIR!\last_profile.txt"
set "FAV_FILE=!STATE_DIR!\favourites.txt"
set "TMPBASE=!TEMP!\brickbat_!RANDOM!!RANDOM!"
set "OUTF=!TMPBASE!_out.txt"
set "ERRF=!TMPBASE!_err.txt"
set "NAMEF=!TMPBASE!_names.txt"
set "HITF=!TMPBASE!_hits.txt"
set "SORTF=!TMPBASE!_sort.txt"
set "VISF=!TMPBASE!_vis.txt"
set "FAVTMP=!TMPBASE!_fav.txt"
set "PRINF=!TMPBASE!_prin.txt"

rem ---- is the Databricks CLI installed, and is it the new one? -----------------
set "CLI_VER="
set "CLI_TAG="
set "OLD_CLI="
where databricks >nul 2>&1
if errorlevel 1 goto :no_cli
for /f "tokens=*" %%v in ('databricks --version 2^>nul') do if not defined CLI_VER set "CLI_VER=%%v"
if not defined CLI_VER goto :no_cli
if /i "!CLI_VER:~0,8!"=="Version " goto :legacy_cli
set "CLI_VER=!CLI_VER:Databricks CLI =!"
set "CLI_TAG=CLI !CLI_VER!"
for /f "tokens=1,2 delims=v." %%a in ("!CLI_VER!") do (
  if "%%a"=="0" if %%b lss 297 set "OLD_CLI=1"
)

set "DBX_PROFILE="
set "DBX_KIND="
set "SCOPE_ORIGIN="
set "PF_N=0"
set "NEED_CHECK=1"

rem ============================================================================
rem  FRONT PAGE
rem ============================================================================
:main
if "!NEED_CHECK!"=="1" (
  cls
  call :banner
  echo(
  echo   !cDim!Checking your profiles and logins...!c0!
  call :check_status
)
cls
call :banner
call :status_panel
echo(
if "!DBX_STATE!"=="IN" goto :main_in
if "!DBX_STATE!"=="OUT" goto :main_out
goto :main_none

:main_in
echo   !cKey![S]!c0! Secrets          !cKey![P]!c0! Switch profile    !cKey![T]!c0! Terminal with this profile
echo   !cKey![L]!c0! Log in again     !cKey![N]!c0! New profile       !cKey![W]!c0! Open workspace in browser
echo   !cKey![O]!c0! Log out          !cKey![I]!c0! Info and update   !cKey![R]!c0! Refresh   !cKey![Q]!c0! Quit
echo(
call :menu SPTLNWOIRQ
if "!MENU_KEY!"=="S" goto :secrets_menu
if "!MENU_KEY!"=="P" goto :switch_profile
if "!MENU_KEY!"=="T" goto :open_terminal
if "!MENU_KEY!"=="L" goto :do_login
if "!MENU_KEY!"=="N" goto :new_profile
if "!MENU_KEY!"=="W" goto :open_workspace
if "!MENU_KEY!"=="O" goto :do_logout
if "!MENU_KEY!"=="I" goto :info
if "!MENU_KEY!"=="R" goto :refresh
if "!MENU_KEY!"=="Q" goto :quit
goto :main

:main_out
echo   !cKey![L]!c0! Log in to !cHead!!DBX_PROFILE!!c0! - your browser opens for the sign-in
echo   !cKey![P]!c0! Switch profile   !cKey![N]!c0! New profile       !cKey![O]!c0! Log out or remove this profile
echo   !cKey![I]!c0! Info and update  !cKey![R]!c0! Refresh           !cKey![Q]!c0! Quit
echo(
call :menu LPNOIRQ
if "!MENU_KEY!"=="L" goto :do_login
if "!MENU_KEY!"=="P" goto :switch_profile
if "!MENU_KEY!"=="N" goto :new_profile
if "!MENU_KEY!"=="O" goto :do_logout
if "!MENU_KEY!"=="I" goto :info
if "!MENU_KEY!"=="R" goto :refresh
if "!MENU_KEY!"=="Q" goto :quit
goto :main

:main_none
echo   !cKey![N]!c0! New profile - connect a workspace, the sign-in happens in your browser
echo   !cKey![I]!c0! Info and update  !cKey![R]!c0! Refresh           !cKey![Q]!c0! Quit
echo(
call :menu NIRQ
if "!MENU_KEY!"=="N" goto :new_profile
if "!MENU_KEY!"=="I" goto :info
if "!MENU_KEY!"=="R" goto :refresh
if "!MENU_KEY!"=="Q" goto :quit
goto :main

:refresh
set "NEED_CHECK=1"
goto :main

rem ============================================================================
rem  PROFILES: switch, log in, new profile, log out
rem ============================================================================
:switch_profile
call :screen "Switch profile"
echo(
for /l %%i in (1,1,!PF_N!) do call :print_profile_row %%i num
echo(
if "!SYNC_CLI_DEFAULT!"=="1" echo   !cDim!The profile you pick also becomes the default for plain databricks commands.!c0!
call :pick_number !PF_N! "   Profile number (blank = back): "
if not defined PICK goto :main
for %%i in (!PICK!) do set "_newp=!PF_NAME_%%i!"
call :set_active "!_newp!"
set "NEED_CHECK=1"
goto :main

:do_login
if not defined DBX_PROFILE goto :new_profile
call :screen "Log in"
echo(
echo   Logging in to !cHead!!DBX_PROFILE!!c0!  !cDim!!DBX_HOST!!c0!
echo   Your browser opens now. Finish the sign-in there and come back to this window.
echo(
databricks auth login --profile "!DBX_PROFILE!"
if errorlevel 1 (
  echo(
  echo   !cErr!The login did not complete.!c0!
  call :pause_any
)
set "NEED_CHECK=1"
goto :main

:new_profile
call :screen "New profile"
echo(
echo   Connect a Databricks workspace. You sign in with your own account in the browser.
echo   !cDim!The CLI cannot create Databricks users - your admins add those - so this adds a profile.!c0!
echo(
echo   Paste the workspace URL. Straight from the browser address bar is fine.
echo   !cDim!For example  https://dbc-a1b2c3d4-e5f6.cloud.databricks.com        AWS!c0!
echo   !cDim!             https://adb-1234567890123456.7.azuredatabricks.net    Azure!c0!
echo   !cDim!             https://1234567890123456.7.gcp.databricks.com         Google Cloud!c0!
echo(
set "NEW_HOST="
set /p "NEW_HOST=!c0!   Workspace URL (blank = back): "
if not defined NEW_HOST goto :main
call :normalize_host
if not defined NEW_HOST goto :new_profile
echo   !cDim!Using !NEW_HOST!!c0!
echo(
echo   Give the profile a short name you will recognise, for example dev, test or prod.
set "NEW_NAME="
set /p "NEW_NAME=!c0!   Profile name (blank = back): "
if not defined NEW_NAME goto :main
set "NEW_NAME=!NEW_NAME:"=!"
call :trim_var NEW_NAME
if not defined NEW_NAME goto :main
set "NEW_NAME=!NEW_NAME: =-!"
set "NEW_NAME=!NEW_NAME:[=!"
if not defined NEW_NAME goto :main
set "NEW_NAME=!NEW_NAME:]=!"
if not defined NEW_NAME goto :main
call :bad_chars NEW_NAME ""
if not errorlevel 1 (
  echo   !cErr!Profile names may use letters, digits, - _ and . only, and not start with -.!c0!
  call :pause_any
  goto :new_profile
)
call :pf_find "!NEW_NAME!"
if not errorlevel 1 (
  echo(
  echo   !cWarn!A profile called !NEW_NAME! already exists.!c0! Pick it with P on the front page, or use another name.
  call :pause_any
  goto :new_profile
)
echo(
echo   !cDim!Opening your browser for the sign-in...!c0!
echo(
databricks auth login --host "!NEW_HOST!" --profile "!NEW_NAME!"
if errorlevel 1 (
  echo(
  echo   !cErr!The login did not complete.!c0!
  call :pause_any
  set "NEED_CHECK=1"
  goto :main
)
call :set_active "!NEW_NAME!"
set "NEED_CHECK=1"
goto :main

:do_logout
if not defined DBX_PROFILE goto :main
call :screen "Log out"
echo(
echo   Profile !cHead!!DBX_PROFILE!!c0!  !cDim!!DBX_HOST!!c0!
echo(
echo   !cKey![Y]!c0! Log out - forget the saved browser login, keep the profile for next time
echo   !cKey![D]!c0! Log out and delete the profile from your .databrickscfg
echo   !cKey![B]!c0! Back
echo(
call :menu YDB
if not defined MENU_KEY goto :main
if "!MENU_KEY!"=="B" goto :main
set "_del="
if "!MENU_KEY!"=="D" set "_del=--delete"
call :dbx auth logout --profile "!DBX_PROFILE!" --auto-approve !_del!
echo(
if "!DBX_RC!"=="0" goto :do_logout_ok
call :show_err
findstr /i /c:"unknown command" "%ERRF%" >nul 2>&1
if not errorlevel 1 echo   !cWarn!Your Databricks CLI is too old for logout - update it from Info.!c0!
call :pause_any
goto :main
:do_logout_ok
for /f "usebackq delims=" %%l in ("%OUTF%") do echo   !cDim!%%l!c0!
echo   !cOk!Logged out of !DBX_PROFILE!.!c0!
if defined _del (
  echo   !cOk!The profile was removed from .databrickscfg.!c0!
  set "DBX_PROFILE="
)
call :pause_any
set "NEED_CHECK=1"
goto :main

:open_terminal
cls
echo(
echo   !cBrand!█ BRICKBAT!c0!  !cDim!·!c0!  !cHead!Terminal for !DBX_PROFILE!!c0!
echo(
echo   Every databricks command in here uses profile !cHead!!DBX_PROFILE!!c0!  !cDim!!DBX_HOST!!c0!
echo   Type !cHead!exit!c0! to go back to BrickBat.
echo(
echo   !cDim!Try:  databricks current-user me     databricks clusters list     databricks secrets list-scopes!c0!
echo(
set "_oldcp=!DATABRICKS_CONFIG_PROFILE!"
set "_oldprompt=!PROMPT!"
set "DATABRICKS_CONFIG_PROFILE=!DBX_PROFILE!"
if defined c0 (set "PROMPT=$E[38;2;255;54;33m[BrickBat:!DBX_PROFILE!]$E[0m $P$G") else (set "PROMPT=[BrickBat:!DBX_PROFILE!] $P$G")
cmd /k
if defined _oldcp (set "DATABRICKS_CONFIG_PROFILE=!_oldcp!") else (set "DATABRICKS_CONFIG_PROFILE=")
if defined _oldprompt (set "PROMPT=!_oldprompt!") else (set "PROMPT=")
set "NEED_CHECK=1"
goto :main

:open_workspace
if defined DBX_HOST start "" "!DBX_HOST!"
goto :main

:info
call :screen "Info"
echo(
set "_cfg=!USERPROFILE!\.databrickscfg"
if defined DATABRICKS_CONFIG_FILE set "_cfg=!DATABRICKS_CONFIG_FILE!"
echo   !cDim!BrickBat          !c0!v!BB_VERSION!
echo   !cDim!Databricks CLI    !c0!!CLI_VER!
echo   !cDim!Profiles file     !c0!!_cfg!
echo   !cDim!Favourites        !c0!!FAV_FILE!
echo   !cDim!Settings          !c0!SYNC_CLI_DEFAULT=!SYNC_CLI_DEFAULT!  LOOKUP_LIMIT=!LOOKUP_LIMIT!
echo   !cDim!                  !c0!ENV_WORDS=!ENV_WORDS!
echo   !cDim!                  change them at the top of brickbat.bat!c0!
if not defined DBX_PROFILE goto :info_menu
echo(
echo   !cDim!databricks auth describe --profile !DBX_PROFILE!!c0!
echo(
databricks auth describe --profile "!DBX_PROFILE!"
:info_menu
echo(
echo   !cKey![U]!c0! Update the Databricks CLI with winget     !cKey![B]!c0! Back
echo(
call :menu UB
if "!MENU_KEY!"=="U" goto :update_cli
goto :main

:update_cli
echo(
winget upgrade --id Databricks.DatabricksCLI -e
echo(
echo   !cDim!If a new version was installed, close this window and start BrickBat again.!c0!
echo   !cDim!After a major upgrade you may have to log in once more per profile.!c0!
call :pause_any
goto :main

rem ============================================================================
rem  SECRETS
rem ============================================================================
:secrets_menu
if "!DBX_KIND!"=="account" (
  call :screen "Secrets"
  echo(
  echo   !cWarn!!DBX_PROFILE! is an account console profile.!c0! Secret scopes live in workspaces,
  echo   so switch to a workspace profile first.
  call :pause_any
  goto :main
)
call :screen "Secrets"
call :load_favs
echo(
echo   !cDim!Secrets live in scopes. Access is granted per scope and covers every secret in it.!c0!
echo(
echo   !cKey![1]!c0! Show all scopes in !cHead!!DBX_PROFILE!!c0!
echo   !cKey![2]!c0! Search scopes by name
echo   !cKey![3]!c0! Compare one scope across environments
echo   !cKey![4]!c0! Create a new scope in !cHead!!DBX_PROFILE!!c0!
if not "!FAV_N!"=="0" echo   !cKey![F]!c0! Open a favourite
echo   !cKey![B]!c0! Back
echo(
echo   !cDim!FAVOURITES!c0!
if "!FAV_N!"=="0" echo   !cDim!  None for !DBX_PROFILE! yet - open one of its scopes and press S.!c0!
for /l %%i in (1,1,!FAV_N!) do call :print_fav_row %%i
echo(
echo   !cDim!Looking inside scopes for a key or someone's access costs one call per scope,!c0!
echo   !cDim!so it is offered once a list is down to !LOOKUP_LIMIT! scopes or fewer.!c0!
echo(
set "_mk=1234B"
if not "!FAV_N!"=="0" set "_mk=1234FB"
call :menu !_mk!
if "!MENU_KEY!"=="1" goto :show_all
if "!MENU_KEY!"=="2" goto :search_scopes
if "!MENU_KEY!"=="3" goto :compare_scope
if "!MENU_KEY!"=="4" goto :scope_create
if "!MENU_KEY!"=="F" goto :fav_open
goto :main

rem ---- open a favourite of the active workspace - 2 calls, like any scope -----
:fav_open
set "PICK=1"
if not "!FAV_N!"=="1" call :pick_number !FAV_N! "   Favourite number (blank = back): "
if not defined PICK goto :secrets_menu
for %%i in (!PICK!) do (
  set "SCOPE=!FAV_SCOPE_%%i!"
  set "SCOPE_TYPE=!FAV_TYPE_%%i!"
)
set "SP=!DBX_PROFILE!"
set "SCOPE_ORIGIN=menu"
goto :scope_page

rem ---- show all scopes of the active profile - one call ------------------------
:show_all
call :screen "Scopes in !DBX_PROFILE!"
echo(
echo   !cDim!Loading scopes...!c0!
call :load_scopes "!DBX_PROFILE!"
if errorlevel 1 (
  echo(
  call :show_err
  call :pause_any
  goto :secrets_menu
)
if "!SC_N!"=="0" (
  echo(
  echo   No scopes in this workspace, or you are not allowed to list them.
  call :pause_any
  goto :secrets_menu
)
set "L_ONE=!DBX_PROFILE!"
set "L_TITLE=Scopes in !DBX_PROFILE!"
set "L_FILTER="
for /l %%i in (1,1,!SC_N!) do (
  set "L_SCOPE_%%i=!SC_NAME_%%i!"
  set "L_TYPE_%%i=!SC_TYPE_%%i!"
)
set "L_N=!SC_N!"
goto :list_show

rem ---- search scope names - one call per environment ---------------------------
:search_scopes
call :screen "Search scopes by name"
echo(
set "Q_SEARCH="
set /p "Q_SEARCH=!c0!   Scope name contains (blank = back): "
if not defined Q_SEARCH goto :secrets_menu
set "Q_SEARCH=!Q_SEARCH:"=!"
call :trim_var Q_SEARCH
if not defined Q_SEARCH goto :secrets_menu
echo(
echo   !cKey![C]!c0! Only !DBX_PROFILE!     !cKey![A]!c0! All logged-in environments     !cKey![B]!c0! Back
echo(
call :menu CAB
if not defined MENU_KEY goto :secrets_menu
if "!MENU_KEY!"=="B" goto :secrets_menu
echo(
echo   !cDim!Searching...!c0!
call :load_profiles
set "L_N=0"
set "L_ONE="
set "L_FILTER="
set "L_TITLE=Scopes matching !Q_SEARCH!"
if "!MENU_KEY!"=="A" goto :search_all
set "L_ONE=!DBX_PROFILE!"
call :pf_find "!DBX_PROFILE!"
if defined _pf call :list_add_env !_pf!
goto :search_done
:search_all
set "_seen=|"
for /l %%i in (1,1,!PF_N!) do call :list_add_env %%i
:search_done
if not "!L_N!"=="0" goto :search_found
echo(
echo   No scope names contain !Q_SEARCH!.
call :pause_any
goto :secrets_menu
:search_found
if not "!L_N!"=="1" goto :list_show
call :list_get 1
set "SCOPE_ORIGIN=menu"
goto :scope_page

rem ---- a list of scopes: filter it, open one, or look inside a few -------------
:list_show
call :screen "!L_TITLE!"
echo(
call :list_visible
if "!V_N!"=="0" (
  echo   !cDim!No scope names in this list contain !L_FILTER!.!c0!
) else (
  call :list_print
)
echo(
if defined L_FILTER (
  echo   !cDim!Filter: !L_FILTER!  -  !V_N! of !L_N! scopes shown!c0!
) else (
  echo   !cDim!!L_N! scopes!c0!
)
echo(
if "!V_N!"=="0" goto :list_menu_empty
if !V_N! leq !LOOKUP_LIMIT! goto :list_menu_small
echo   !cKey![O]!c0! Open a scope     !cKey![F]!c0! Filter by name     !cKey![B]!c0! Back
echo   !cDim!Filter down to !LOOKUP_LIMIT! scopes or fewer to look inside them for a key or someone's access.!c0!
echo(
call :menu OFB
if "!MENU_KEY!"=="O" goto :list_open
if "!MENU_KEY!"=="F" goto :list_filter
goto :secrets_menu
:list_menu_small
echo   !cKey![O]!c0! Open a scope     !cKey![F]!c0! Filter by name     !cKey![B]!c0! Back
echo   !cKey![V]!c0! Show the keys and access of these !V_N! scopes
echo   !cKey![U]!c0! Add or update a key in some or all of them
echo   !cKey![G]!c0! Grant or change access in some or all of them
echo   !cKey![K]!c0! Find a key in these !V_N! scopes
echo   !cKey![P]!c0! Check someone's access on these !V_N! scopes
echo(
call :menu OFBVUGKP
if "!MENU_KEY!"=="O" goto :list_open
if "!MENU_KEY!"=="F" goto :list_filter
if "!MENU_KEY!"=="V" goto :list_view
if "!MENU_KEY!"=="U" goto :list_set
if "!MENU_KEY!"=="G" goto :list_grant
if "!MENU_KEY!"=="K" goto :lookup_key
if "!MENU_KEY!"=="P" goto :lookup_access
goto :secrets_menu
:list_menu_empty
echo   !cKey![F]!c0! Filter by name     !cKey![B]!c0! Back
echo(
call :menu FB
if "!MENU_KEY!"=="F" goto :list_filter
goto :secrets_menu

:list_open
call :pick_number !L_N! "   Scope number (blank = back): "
if not defined PICK goto :list_show
call :list_get !PICK!
set "SCOPE_ORIGIN=list"
goto :scope_page

:list_filter
echo(
set "_in="
set /p "_in=!c0!   Scope name contains (blank = show the whole list): "
if defined _in set "_in=!_in:"=!"
call :trim_var _in
set "L_FILTER=!_in!"
goto :list_show

rem ---- the keys and access of every scope shown - two calls each -----------------
:list_view
if !V_N! gtr !LOOKUP_LIMIT! goto :list_show
set "SP_FAV="
call :screen "Keys and access of !V_N! scopes"
echo(
for /f "usebackq delims=" %%n in ("%VISF%") do call :list_view_one %%n
call :pause_any
goto :list_show

:list_view_one
rem %1 = list entry number. Its environment, then its keys and access
call :list_get %~1
set "_p=!SP!"
set "_h="
call :pf_find "!SP!"
if defined _pf for %%i in (!_pf!) do set "_h=!PF_HOST_%%i!"
echo   !cHead!!SP!!c0!  !cDim!!_h!!c0!
call :compare_show "!SCOPE!"
exit /b 0

rem ---- one key in the scopes picked - one call each to check, one to save -------
:list_set
if !V_N! gtr !LOOKUP_LIMIT! goto :list_show
echo(
echo   Adds or updates one key in the scopes you pick, for example the same scope in each environment.
echo   !cDim!Key names may use letters, digits, - _ and . only.!c0!
set "KEY="
set /p "KEY=!c0!   Key (blank = back): "
if not defined KEY goto :list_show
set "KEY=!KEY:"=!"
if not defined KEY goto :list_show
set "KEY=!KEY: =!"
if not defined KEY goto :list_show
call :bad_chars KEY ""
if not errorlevel 1 (
  echo   !cErr!Key names may use letters, digits, - _ and . only, and not start with -.!c0!
  call :pause_any
  goto :list_show
)
call :pick_scopes keys
if errorlevel 1 goto :list_show
call :screen "Add or update !KEY! in !T_N! scopes"
echo(
echo   !cDim!Checking which of them have !KEY! already - one call per scope.!c0!
echo(
for /l %%i in (1,1,!T_N!) do call :list_set_row %%i
echo(
echo   !cKey![T]!c0! Type or paste a value for each scope - the CLI asks once per scope, hidden
echo   !cKey![F]!c0! The same value for every scope, read from a file
echo   !cKey![B]!c0! Back
echo(
call :menu TFB
if "!MENU_KEY!"=="T" goto :list_set_typed
if "!MENU_KEY!"=="F" goto :list_set_file
goto :list_show
:list_set_typed
set "T_MODE=typed"
goto :list_set_go
:list_set_file
echo(
call :ask_value_file
if errorlevel 1 goto :list_show
set "T_MODE=file"
:list_set_go
echo(
echo   Add or update !cHead!!KEY!!c0! in these !T_N! scopes?
call :confirm
if not defined CONFIRMED goto :list_show
if "!T_MODE!"=="typed" (
  echo(
  call :typed_intro
  echo   !cDim!It asks once for each scope, named just above its prompt.!c0!
)
set "T_OK=0"
set "T_FAIL="
for /l %%i in (1,1,!T_N!) do call :list_set_one %%i
echo(
if "!T_OK!"=="!T_N!" (
  echo   !cOk!Saved !KEY! in all !T_N! scopes.!c0!
) else (
  echo   !cWarn!Saved !KEY! in !T_OK! of !T_N! scopes. Not saved in:!T_FAIL!!c0!
)
if "!T_MODE!"=="typed" if not "!T_OK!"=="0" call :clear_clipboard
call :pause_any
goto :list_show

:list_set_row
rem %1 = target number. One call: does that scope have KEY already?
call :list_get !T_E_%~1!
call :load_secrets "!SP!" "!SCOPE!"
if errorlevel 1 (
  set "_st=!cWarn!could not check: !SE_ERR!!c0!"
) else (
  set "_st=!cOk!new key!c0!"
  for /l %%k in (1,1,!SE_N!) do if /i "!SE_NAME_%%k!"=="!KEY!" set "_st=!cWarn!replaces the current value!c0!"
)
call :plan_row %~1
exit /b 0

:list_set_one
rem %1 = target number. Saves KEY there - one call
call :list_get !T_E_%~1!
echo(
echo   !cHead!!SP!!c0!  !SCOPE!  !cDim!%~1 of !T_N!!c0!
if "!T_MODE!"=="file" (
  set "_rc=0"
  databricks secrets put-secret "!SCOPE!" "!KEY!" -p "!SP!" --log-level error < "!VFILE!" || set "_rc=1"
) else (
  call :put_typed
)
if "!_rc!"=="0" (
  set /a T_OK+=1
  echo   !cOk!Saved.!c0!
) else (
  set "T_FAIL=!T_FAIL! !SP!:!SCOPE!"
  echo   !cErr!Not saved - see the message above.!c0!
)
exit /b 0

rem ---- one principal's access in the scopes picked - one call each to read -------
:list_grant
if !V_N! gtr !LOOKUP_LIMIT! goto :list_show
echo(
echo   Gives one principal the same access in the scopes you pick. A user e-mail, a group name
echo   or a service principal's application ID.
echo   !cDim!users means everyone in the workspace. Existing access for the same principal is replaced.!c0!
set "PRIN="
set /p "PRIN=!c0!   Principal (blank = back): "
if not defined PRIN goto :list_show
set "PRIN=!PRIN:"=!"
call :trim_var PRIN
if not defined PRIN goto :list_show
echo(
echo   !cKey![R]!c0! READ     read secrets and list the keys
echo   !cKey![W]!c0! WRITE    READ, plus add, update and delete secrets
echo   !cKey![M]!c0! MANAGE   WRITE, plus change who has access
echo   !cKey![B]!c0! Back
echo(
call :menu RWMB
set "PERM="
if "!MENU_KEY!"=="R" set "PERM=READ"
if "!MENU_KEY!"=="W" set "PERM=WRITE"
if "!MENU_KEY!"=="M" set "PERM=MANAGE"
if not defined PERM goto :list_show
call :pick_scopes access
if errorlevel 1 goto :list_show
call :screen "Give !PRIN! !PERM! in !T_N! scopes"
echo(
echo   !cDim!Reading the access on each of them - one call per scope, and it needs MANAGE.!c0!
echo(
set "T_GO=0"
for /l %%i in (1,1,!T_N!) do call :list_grant_row %%i
echo(
if "!T_GO!"=="0" (
  echo   Nothing to change.
  call :pause_any
  goto :list_show
)
echo   Give !cHead!!PRIN!!c0! !PERM! in the !T_GO! scopes that change?
call :confirm
if not defined CONFIRMED goto :list_show
set "T_OK=0"
set "T_FAIL="
for /l %%i in (1,1,!T_N!) do if defined T_DO_%%i call :list_grant_one %%i
echo(
if "!T_OK!"=="!T_GO!" (
  echo   !cOk!!PRIN! now has !PERM! in all !T_GO! scopes.!c0!
) else (
  echo   !cWarn!!PRIN! now has !PERM! in !T_OK! of !T_GO! scopes. Not changed in:!T_FAIL!!c0!
)
call :pause_any
goto :list_show

:list_grant_row
rem %1 = target number. One call: what PRIN has there now, and whether it changes
set "T_DO_%~1="
call :list_get !T_E_%~1!
call :load_acls "!SP!" "!SCOPE!"
if errorlevel 1 (
  set "_st=!cWarn!skipped - its access can't be read: !AC_ERR!!c0!"
  call :plan_row %~1
  exit /b 0
)
call :acl_state
set "T_CUR_%~1=!_cur!"
if /i "!_cur!"=="!PERM!" (
  set "_st=!cDim!skipped - has !PERM! already!c0!"
  call :plan_row %~1
  exit /b 0
)
set "T_DO_%~1=1"
set /a T_GO+=1
if defined _cur (set "_st=!cWarn!!_cur! now, becomes !PERM!!c0!") else set "_st=!cOk!new!c0!"
call :plan_row %~1
if "!_cur!"=="MANAGE" if not "!PERM!"=="MANAGE" if "!_mg!"=="1" echo   !cWarn!        The only MANAGE entry there - afterwards only a workspace admin can change its access.!c0!
if /i "!PRIN!"=="!DBX_USER!" if not "!PERM!"=="MANAGE" echo   !cWarn!        That is you - with !PERM! you can no longer manage access there.!c0!
exit /b 0

:list_grant_one
rem %1 = target number. Gives PRIN PERM there - one call, three when an entry is replaced
call :list_get !T_E_%~1!
set "_cur=!T_CUR_%~1!"
echo(
echo   !cHead!!SP!!c0!  !SCOPE!
call :acl_apply
if "!DBX_RC!"=="0" (
  set /a T_OK+=1
  echo   !cOk!Done.!c0!
) else (
  call :show_err
  set "T_FAIL=!T_FAIL! !SP!:!SCOPE!"
)
exit /b 0

:pick_scopes
rem %1 = keys leaves out Azure Key Vault scopes, whose secrets live in the Key Vault.
rem Asks for numbers from the list shown -> T_N and T_E_i, the entry numbers. errorlevel 1 = back
set "_vis= "
for /f "usebackq delims=" %%n in ("%VISF%") do set "_vis=!_vis!%%n "
:pick_scopes_ask
set "_in="
set /p "_in=!c0!   Scope numbers from the list, separated by spaces (A = all, blank = back): "
if not defined _in exit /b 1
set "_in=!_in:"=!"
call :trim_var _in
if not defined _in exit /b 1
if /i "!_in!"=="A" set "_in=!_vis!"
rem Only digits, spaces and commas - a for loop would read * and ? as file patterns
for /f "delims=0123456789 ," %%x in ("!_in!") do (
  echo   !cErr!Type numbers from the list, like 3 6 8, or A for all.!c0!
  goto :pick_scopes_ask
)
set "T_N=0"
set "_bad="
set "_akv="
for %%t in (!_in!) do (
  if "!_vis: %%t =!"=="!_vis!" (set "_bad=!_bad! %%t") else call :pick_scopes_add %%t %1
)
if defined _bad (
  echo   !cErr!Not in the list:!_bad!!c0!
  goto :pick_scopes_ask
)
if defined _akv echo   !cDim!Left out - Azure Key Vault scopes get their secrets in the Key Vault:!_akv!!c0!
if "!T_N!"=="0" goto :pick_scopes_ask
exit /b 0

:pick_scopes_add
rem %1 = list entry number, %2 = keys or access. Adds it to T_E_i once
for /l %%i in (1,1,!T_N!) do if "!T_E_%%i!"=="%~1" exit /b 0
if "%~2"=="keys" if /i "!L_TYPE_%~1!"=="AZURE_KEYVAULT" (
  set "_akv=!_akv! %~1"
  exit /b 0
)
set /a T_N+=1
set "T_E_!T_N!=%~1"
exit /b 0

:plan_row
rem %1 = target number, after list_get. Its list number, environment, scope and _st
set "_num=    !T_E_%~1!"
set "_pp=!SP!"
call :pad _pp 14
set "_nm=!SCOPE!"
call :pad _nm 44
echo  !cKey!!_num:~-4!!c0!  !_pp! !_nm! !_st!
exit /b 0

rem ---- look inside the scopes shown - one call each, never above the limit -----
:lookup_key
echo(
echo   !cDim!Lists the keys in each of the !V_N! scopes shown - one call per scope.!c0!
set "Q_SEARCH="
set /p "Q_SEARCH=!c0!   Part of the key name (blank = back): "
if not defined Q_SEARCH goto :list_show
set "Q_SEARCH=!Q_SEARCH:"=!"
call :trim_var Q_SEARCH
if not defined Q_SEARCH goto :list_show
set "LK_MODE=key"
set "M_WHAT=secret keys containing !Q_SEARCH!"
goto :lookup_run

:lookup_access
echo(
echo   A user e-mail, a group name or a service principal's application ID.
echo   !cDim!Lists the access on each of the !V_N! scopes shown - one call per scope. Only direct!c0!
echo   !cDim!entries are found, not access through a group, and it needs MANAGE on the scope.!c0!
set "Q_PRIN="
set /p "Q_PRIN=!c0!   Principal (blank = back): "
if not defined Q_PRIN goto :list_show
set "Q_PRIN=!Q_PRIN:"=!"
call :trim_var Q_PRIN
if not defined Q_PRIN goto :list_show
set "LK_MODE=acl"
set "M_WHAT=access entries for !Q_PRIN!"
goto :lookup_run

:lookup_run
if !V_N! gtr !LOOKUP_LIMIT! goto :list_show
set "M_N=0"
set "LK_DENIED=0"
set "LK_FAILED=0"
set "_done=0"
echo(
if not defined ESC <nul set /p "=   Checking !V_N! scopes "
for /f "usebackq delims=" %%n in ("%VISF%") do call :lookup_one %%n
if defined ESC (
  echo(
) else (
  echo  done
)
set "M_NOTE="
set "M_NOTE2="
set "_why=you cannot read them"
if "!LK_MODE!"=="acl" set "_why=you do not have MANAGE on them"
if not "!LK_DENIED!"=="0" set "M_NOTE=Scopes skipped because !_why!: !LK_DENIED!"
if not "!LK_FAILED!"=="0" set "M_NOTE2=Scopes where the call failed - check your connection and try again: !LK_FAILED!"
goto :find_results

rem ---- one scope: secrets, access and actions ----------------------------------
:scope_page
call :sp_screen
echo(
echo   !cDim!Loading secrets and access for !SCOPE! in !SP!...!c0!
call :load_secrets "!SP!" "!SCOPE!"
call :load_acls "!SP!" "!SCOPE!"
:scope_page_show
call :sp_screen
set "SP_FAV="
call :is_fav "!SP_HOST!" "!SCOPE!"
if not errorlevel 1 set "SP_FAV=1"
set "_ty=Databricks"
if /i "!SCOPE_TYPE!"=="AZURE_KEYVAULT" set "_ty=Azure Key Vault - its secrets are managed in the Key Vault"
set "_favtag="
if defined SP_FAV set "_favtag=  !cWarn!favourite!c0!"
set "_fl=Save as favourite"
if defined SP_FAV set "_fl=Remove from favourites"
call :pad _fl 27
echo(
echo   !cDim!Scope        !c0!!cHead!!SCOPE!!c0!!_favtag!
echo   !cDim!Backend      !c0!!_ty!
echo   !cDim!Environment  !c0!!SP!  !cDim!!SP_HOST!!c0!
echo(
echo   !cHead!SECRETS!c0!  !cDim!keys only, values are never shown!c0!
call :print_secrets
echo(
echo   !cHead!ACCESS!c0!  !cDim!applies to every secret in this scope!c0!
call :print_acls
echo(
echo   !cKey![A]!c0! Add or update a secret     !cKey![D]!c0! Delete a secret
echo   !cKey![G]!c0! Grant or change access     !cKey![X]!c0! Remove access
echo   !cKey![S]!c0! !_fl!!cKey![E]!c0! This scope in every environment
echo   !cKey![Z]!c0! Delete this scope          !cKey![R]!c0! Reload        !cKey![B]!c0! Back
echo(
call :menu ADGXSEZRB
if "!MENU_KEY!"=="A" goto :secret_put
if "!MENU_KEY!"=="D" goto :secret_delete
if "!MENU_KEY!"=="G" goto :acl_put
if "!MENU_KEY!"=="X" goto :acl_delete
if "!MENU_KEY!"=="S" goto :fav_toggle
if "!MENU_KEY!"=="E" goto :compare_from_scope
if "!MENU_KEY!"=="Z" goto :scope_delete
if "!MENU_KEY!"=="R" goto :scope_page
if "!MENU_KEY!"=="B" goto :scope_back
goto :scope_page_show

:sp_screen
rem The scope page's header names the scope's own environment, which differs from the
rem active profile when the scope was found in another environment
set "SP_HOST="
call :pf_find "!SP!"
if defined _pf for %%i in (!_pf!) do set "SP_HOST=!PF_HOST_%%i!"
set "SCR_PROF=!SP!"
set "SCR_HOST=!SP_HOST!"
call :screen "Scope !SCOPE!"
exit /b 0

:scope_back
if "!SCOPE_ORIGIN!"=="list" goto :list_show
if "!SCOPE_ORIGIN!"=="results" goto :find_results_show
goto :secrets_menu

rem ---- save or remove a favourite - no calls, a line in favourites.txt --------
:fav_toggle
if not defined SP_HOST goto :scope_page_show
call :fav_host "!SP_HOST!"
if defined SP_FAV (
  call :fav_remove "!_fh!" "!SCOPE!"
  goto :scope_page_show
)
set "_ft=!SCOPE_TYPE!"
if not defined _ft set "_ft=DATABRICKS"
call :fav_remove "!_fh!" "!SCOPE!"
(>>"%FAV_FILE%" echo(!_fh! !SCOPE! !_ft!) 2>nul
goto :scope_page_show

rem ---- add or update a secret --------------------------------------------------
:secret_put
echo(
if /i "!SCOPE_TYPE!"=="AZURE_KEYVAULT" (
  echo   !cWarn!This scope reads its secrets from Azure Key Vault.!c0!
  echo   Add or change them in the Key Vault in the Azure portal - Databricks cannot write to it.
  call :pause_any
  goto :scope_page_show
)
echo   Key names may use letters, digits, - _ and . only. An existing key gets a new value.
set "KEY="
set /p "KEY=!c0!   Key (blank = back): "
if not defined KEY goto :scope_page_show
set "KEY=!KEY:"=!"
if not defined KEY goto :scope_page_show
set "KEY=!KEY: =!"
if not defined KEY goto :scope_page_show
call :bad_chars KEY ""
if not errorlevel 1 (
  echo   !cErr!Key names may use letters, digits, - _ and . only, and not start with -.!c0!
  call :pause_any
  goto :scope_page_show
)
set "_exists="
for /l %%i in (1,1,!SE_N!) do if /i "!SE_NAME_%%i!"=="!KEY!" set "_exists=1"
if defined _exists echo   !cWarn!!KEY! already exists in !SP! - its value will be replaced.!c0!
echo(
echo   !cKey![T]!c0! Type or paste the value - hidden, one line only
echo   !cKey![F]!c0! Read the value from a file - for multi-line values like JSON keys or certificates
echo   !cKey![B]!c0! Back
echo(
call :menu TFB
if "!MENU_KEY!"=="T" goto :secret_put_typed
if "!MENU_KEY!"=="F" goto :secret_put_file
goto :scope_page_show

:secret_put_typed
echo(
call :typed_intro
echo(
call :put_typed
if "!_rc!"=="0" call :clear_clipboard
goto :secret_put_done

:secret_put_file
echo(
call :ask_value_file
if errorlevel 1 goto :scope_page_show
rem || also catches a file that can't be opened, where cmd skips the command and keeps ERRORLEVEL
set "_rc=0"
databricks secrets put-secret "!SCOPE!" "!KEY!" -p "!SP!" --log-level error < "!VFILE!" || set "_rc=1"

:secret_put_done
echo(
if "!_rc!"=="0" (
  echo   !cOk!Saved !KEY! in !SCOPE! in !SP!.!c0!
) else (
  echo   !cErr!The secret was not saved - see the message above.!c0!
)
call :pause_any
goto :scope_page

rem ---- delete a secret ---------------------------------------------------------
:secret_delete
echo(
if /i "!SCOPE_TYPE!"=="AZURE_KEYVAULT" (
  echo   !cWarn!This scope reads its secrets from Azure Key Vault - delete them in the Key Vault.!c0!
  call :pause_any
  goto :scope_page_show
)
if not "!SE_N!"=="0" goto :secret_delete_pick
echo   There are no secrets to delete.
call :pause_any
goto :scope_page_show
:secret_delete_pick
call :pick_number !SE_N! "   Number of the secret to delete (blank = back): "
if not defined PICK goto :scope_page_show
for %%i in (!PICK!) do set "KEY=!SE_NAME_%%i!"
echo(
echo   Delete !cHead!!KEY!!c0! from !SCOPE! in !SP!? Jobs and notebooks that read it will fail.
call :confirm
if not defined CONFIRMED goto :scope_page_show
call :dbx secrets delete-secret "!SCOPE!" "!KEY!" -p "!SP!"
set "MSG=Deleted !KEY!."
call :report
goto :scope_page

rem ---- grant or change access ---------------------------------------------------
:acl_put
echo(
if defined AC_ERR (
  echo   !cWarn!The access list could not be read, so a change here is not safe. You need MANAGE, or press R to reload.!c0!
  call :pause_any
  goto :scope_page_show
)
echo   Who should get access? A user e-mail, a group name or a service principal's application ID.
echo   !cDim!users means everyone in the workspace. Existing access for the same principal is replaced.!c0!
set "PRIN="
set /p "PRIN=!c0!   Principal (blank = back): "
if not defined PRIN goto :scope_page_show
set "PRIN=!PRIN:"=!"
call :trim_var PRIN
if not defined PRIN goto :scope_page_show
echo(
echo   !cKey![R]!c0! READ     read secrets and list the keys
echo   !cKey![W]!c0! WRITE    READ, plus add, update and delete secrets
echo   !cKey![M]!c0! MANAGE   WRITE, plus change who has access
echo   !cKey![B]!c0! Back
echo(
call :menu RWMB
set "PERM="
if "!MENU_KEY!"=="R" set "PERM=READ"
if "!MENU_KEY!"=="W" set "PERM=WRITE"
if "!MENU_KEY!"=="M" set "PERM=MANAGE"
if not defined PERM goto :scope_page_show
call :acl_state
echo(
if /i "!_cur!"=="!PERM!" (
  echo   !cDim!!PRIN! already has !PERM! - nothing to change.!c0!
  call :pause_any
  goto :scope_page_show
)
if defined _cur echo   !cDim!!PRIN! has !_cur! now - it is replaced.!c0!
if "!_cur!"=="MANAGE" if not "!PERM!"=="MANAGE" if "!_mg!"=="1" echo   !cWarn!This is the only MANAGE entry - afterwards only a workspace admin can change access here.!c0!
if /i "!PRIN!"=="!DBX_USER!" if not "!PERM!"=="MANAGE" echo   !cWarn!That is you - with !PERM! you can no longer manage access on this scope.!c0!
echo   Give !cHead!!PRIN!!c0! !PERM! on !SCOPE! in !SP!?
call :confirm
if not defined CONFIRMED goto :scope_page_show
call :acl_apply
set "MSG=!PRIN! now has !PERM! on !SCOPE!."
call :report
goto :scope_page

rem ---- remove access -----------------------------------------------------------
:acl_delete
echo(
if defined AC_ERR (
  echo   !cWarn!You need MANAGE on this scope to change its access.!c0!
  call :pause_any
  goto :scope_page_show
)
if not "!AC_N!"=="0" goto :acl_delete_pick
echo   There are no access entries to remove.
call :pause_any
goto :scope_page_show
:acl_delete_pick
call :pick_number !AC_N! "   Number of the access entry to remove (blank = back): "
if not defined PICK goto :scope_page_show
for %%i in (!PICK!) do (
  set "PRIN=!AC_PRIN_%%i!"
  set "PERM=!AC_PERM_%%i!"
)
set "_mg=0"
for /l %%i in (1,1,!AC_N!) do if "!AC_PERM_%%i!"=="MANAGE" set /a _mg+=1
echo(
if "!PERM!"=="MANAGE" if "!_mg!"=="1" echo   !cWarn!This is the only MANAGE entry - afterwards only a workspace admin can change access here.!c0!
if /i "!PRIN!"=="!DBX_USER!" echo   !cWarn!That is your own entry - you may lose access to this scope.!c0!
echo   Remove !PERM! for !cHead!!PRIN!!c0! on !SCOPE! in !SP!?
call :confirm
if not defined CONFIRMED goto :scope_page_show
set "DBX_ARGS=secrets delete-acl "!SCOPE!" "!PRIN!" -p "!SP!""
call :dbx_args
set "MSG=Removed the access for !PRIN!."
call :report
goto :scope_page

rem ---- delete the scope --------------------------------------------------------
:scope_delete
echo(
echo   !cErr!Deleting !SCOPE! in !SP! removes it together with every secret in it. This cannot be undone.!c0!
if /i "!SCOPE_TYPE!"=="AZURE_KEYVAULT" echo   !cDim!For a Key Vault-backed scope only the link goes - the Key Vault and its secrets stay.!c0!
set "_c="
set /p "_c=!c0!   Type the scope name to confirm (blank = back): "
if "!_c!"=="!SCOPE!" goto :scope_delete_go
echo   Nothing was deleted.
call :pause_any
goto :scope_page_show
:scope_delete_go
call :dbx secrets delete-scope "!SCOPE!" -p "!SP!"
set "MSG=Scope !SCOPE! deleted in !SP!."
call :report
if not "!DBX_RC!"=="0" goto :scope_page
if defined SP_FAV (
  call :fav_host "!SP_HOST!"
  call :fav_remove "!_fh!" "!SCOPE!"
)
goto :secrets_menu

rem ---- create a scope ----------------------------------------------------------
:scope_create
call :screen "Create a scope in !DBX_PROFILE!"
echo(
echo   Scope names may use letters, digits, - _ and . and be up to 128 characters.
set "NEWSCOPE="
set /p "NEWSCOPE=!c0!   New scope name (blank = back): "
if not defined NEWSCOPE goto :secrets_menu
set "NEWSCOPE=!NEWSCOPE:"=!"
if not defined NEWSCOPE goto :secrets_menu
set "NEWSCOPE=!NEWSCOPE: =!"
if not defined NEWSCOPE goto :secrets_menu
call :bad_chars NEWSCOPE "@"
if not errorlevel 1 (
  echo   !cErr!Scope names may use letters, digits, - _ . and @ only, and not start with -.!c0!
  call :pause_any
  goto :scope_create
)
set "_akv="
if defined DBX_HOST if not "!DBX_HOST:azuredatabricks=!"=="!DBX_HOST!" set "_akv=1"
if not defined _akv goto :scope_create_manage
echo(
echo   !cKey![D]!c0! Databricks-backed - created right here
echo   !cKey![K]!c0! Azure Key Vault-backed - opens the workspace page, these can only be made in the UI
echo   !cKey![B]!c0! Back
echo(
call :menu DKB
if "!MENU_KEY!"=="K" goto :scope_create_akv
if not "!MENU_KEY!"=="D" goto :secrets_menu
:scope_create_manage
echo(
echo   Who gets MANAGE from the start?
echo   !cKey![M]!c0! Only me - recommended, grant others afterwards
echo   !cKey![A]!c0! All users in the workspace - needed where access control per user is not available
echo(
call :menu MA
if not defined MENU_KEY goto :secrets_menu
set "_imp="
if "!MENU_KEY!"=="A" set "_imp=--initial-manage-principal users"
call :dbx secrets create-scope "!NEWSCOPE!" -p "!DBX_PROFILE!" !_imp!
set "MSG=Scope !NEWSCOPE! created."
call :report
if not "!DBX_RC!"=="0" goto :secrets_menu
set "SP=!DBX_PROFILE!"
set "SCOPE=!NEWSCOPE!"
set "SCOPE_TYPE=DATABRICKS"
set "SCOPE_ORIGIN=menu"
goto :scope_page
:scope_create_akv
start "" "!DBX_HOST!#secrets/createScope"
echo(
echo   The Create Secret Scope page is opening in your browser - use the name !cHead!!NEWSCOPE!!c0! there.
call :pause_any
goto :secrets_menu

rem ---- results of a lookup -----------------------------------------------------
:find_results
echo(
if not "!M_N!"=="0" goto :find_results_show
echo   Nothing found.
if defined M_NOTE echo   !cDim!!M_NOTE!!c0!
if defined M_NOTE2 echo   !cDim!!M_NOTE2!!c0!
call :pause_any
goto :list_show
:find_results_show
call :screen "Results"
echo(
echo   !cDim!!M_WHAT!!c0!
echo(
for /l %%i in (1,1,!M_N!) do call :print_match %%i
echo(
if defined M_NOTE echo   !cDim!!M_NOTE!!c0!
if defined M_NOTE2 echo   !cDim!!M_NOTE2!!c0!
call :pick_number !M_N! "   Open a result by number (blank = back): "
if not defined PICK goto :list_show
for %%i in (!PICK!) do (
  set "SP=!M_PROF_%%i!"
  set "SCOPE=!M_SCOPE_%%i!"
  set "SCOPE_TYPE=!M_TYPE_%%i!"
)
set "SCOPE_ORIGIN=results"
goto :scope_page

rem ---- one scope in every environment ------------------------------------------
:compare_scope
call :screen "Compare a scope across environments"
echo(
echo   Type the scope name as it is in one environment. When the name has an environment
echo   word in it, like the dev in analytics.dev.secrets or analytics_dev, the other
echo   environments are searched with that word swapped - qa, prod and so on.
echo(
set "Q_SCOPE="
set /p "Q_SCOPE=!c0!   Scope name (blank = back): "
if not defined Q_SCOPE goto :secrets_menu
set "Q_SCOPE=!Q_SCOPE:"=!"
if not defined Q_SCOPE goto :secrets_menu
set "Q_SCOPE=!Q_SCOPE: =!"
if not defined Q_SCOPE goto :secrets_menu
call :bad_chars Q_SCOPE "@"
if not errorlevel 1 (
  echo   !cErr!Scope names may use letters, digits, - _ . and @ only, and not start with -.!c0!
  call :pause_any
  goto :compare_scope
)
set "CMP_BACK=menu"
goto :compare_run

:compare_from_scope
set "Q_SCOPE=!SCOPE!"
set "CMP_BACK=scope"
:compare_run
call :scope_variants "!Q_SCOPE!"
set "_title=!Q_SCOPE!"
if defined VAR_PAT set "_title=!VAR_PAT!"
call :screen "!_title! in every environment"
echo(
if defined VAR_PAT echo   !cDim!* is one of: !ENV_WORDS!!c0!
echo   !cDim!Checking logins...!c0!
call :load_profiles
echo(
set "_seen=|"
for /l %%i in (1,1,!PF_N!) do call :compare_env %%i
call :clear_variants
call :pause_any
if "!CMP_BACK!"=="scope" goto :scope_page
goto :secrets_menu

rem ============================================================================
rem  SUBROUTINES - screens and status
rem ============================================================================
:banner
echo(
echo   !cB1!██████╗ ██████╗ ██╗ ██████╗██╗  ██╗██████╗  █████╗ ████████╗!c0!
echo   !cB2!██╔══██╗██╔══██╗██║██╔════╝██║ ██╔╝██╔══██╗██╔══██╗╚══██╔══╝!c0!
echo   !cB3!██████╔╝██████╔╝██║██║     █████╔╝ ██████╔╝███████║   ██║!c0!
echo   !cB4!██╔══██╗██╔══██╗██║██║     ██╔═██╗ ██╔══██╗██╔══██║   ██║!c0!
echo   !cB5!██████╔╝██║  ██║██║╚██████╗██║  ██╗██████╔╝██║  ██║   ██║!c0!
echo   !cB6!╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝   ╚═╝!c0!
echo   !cDim!a menu for the Databricks CLI  ·  unofficial  ·  v!BB_VERSION!      !CLI_TAG!!c0!
exit /b 0

:screen
set "_title=%~1"
cls
echo(
echo   !cBrand!█ BRICKBAT!c0!  !cDim!·!c0!  !cHead!!_title!!c0!
if defined SCR_PROF (
  echo   !cDim!profile !SCR_PROF!   !SCR_HOST!!c0!
  if not "!SCR_PROF!"=="!DBX_PROFILE!" echo   !cWarn!Not your active profile !DBX_PROFILE! - changes on this page go to !SCR_PROF!.!c0!
) else if defined DBX_PROFILE echo   !cDim!profile !DBX_PROFILE!   !DBX_HOST!!c0!
set "SCR_PROF="
echo   !cDim!──────────────────────────────────────────────────────────────────────────────!c0!
exit /b 0

:status_panel
echo(
if defined OLD_CLI echo   !cWarn!Your Databricks CLI !CLI_VER! is old - logout and profile switching need v0.297 or newer. Update it under Info.!c0!
if "!DBX_STATE!"=="ERR" (
  echo   !cErr!Could not read your profiles.!c0! !DBX_ERR!
  exit /b 0
)
if "!PF_N!"=="0" (
  echo   !cWarn!No profiles yet.!c0! Press N to connect your first workspace.
  exit /b 0
)
set "_tag="
if "!DBX_ISDEFAULT!"=="true" set "_tag=   !cDim!CLI default!c0!"
echo   !cDim!Profile    !c0!!cHead!!DBX_PROFILE!!c0!!_tag!
echo   !cDim!Workspace  !c0!!DBX_HOST!
if "!DBX_STATE!"=="IN" (
  echo   !cDim!Status     !c0!!cOk!● Logged in!c0! as !cHead!!DBX_USER!!c0!
) else (
  echo   !cDim!Status     !c0!!cErr!● Not logged in!c0!  !cDim!no login yet, it expired, or the workspace is unreachable - VPN?!c0!
)
if defined ENV_AUTH echo   !cWarn!Note:!c0! !cDim!BrickBat ignores!ENV_AUTH! set in Windows and uses the profile shown.!c0!
if defined DATABRICKS_CONFIG_PROFILE if not "!DATABRICKS_CONFIG_PROFILE!"=="!DBX_PROFILE!" echo   !cWarn!Note:!c0! !cDim!DATABRICKS_CONFIG_PROFILE=!DATABRICKS_CONFIG_PROFILE! is set in Windows and overrides the default for plain databricks commands.!c0!
echo(
echo   !cDim!ENVIRONMENTS!c0!
for /l %%i in (1,1,!PF_N!) do call :print_profile_row %%i
exit /b 0

:print_profile_row
rem %1 = profile index, %2 = num to show a selection number
set "_n=!PF_NAME_%~1!"
call :pad _n 16
set "_h=!PF_HOST_%~1!"
set "_mark=    "
if "!PF_NAME_%~1!"=="!DBX_PROFILE!" set "_mark=  !cBrand!►!c0! "
set "_num="
if "%~2"=="num" (
  set "_num=   %~1"
  set "_num=!cKey!!_num:~-2!!c0!  "
)
if "!PF_VALID_%~1!"=="true" (
  set "_s=!cOk!● logged in    !c0!"
) else (
  set "_s=!cErr!○ not logged in!c0!"
)
set "_x="
if "!PF_KIND_%~1!"=="account" set "_x=!_x!  !cDim!account console!c0!"
if "!PF_DEFAULT_%~1!"=="true" set "_x=!_x!  !cDim!CLI default!c0!"
echo !_mark!!_num!!_n! !_s!  !cDim!!_h!!c0!!_x!
exit /b 0

:check_status
set "NEED_CHECK=0"
set "DBX_STATE=NONE"
set "DBX_USER="
set "DBX_HOST="
set "DBX_ERR="
set "DBX_ISDEFAULT="
set "DBX_KIND="
call :load_profiles
if errorlevel 1 (
  set "DBX_STATE=ERR"
  call :first_err DBX_ERR
  exit /b 0
)
if "!PF_N!"=="0" (
  set "DBX_PROFILE="
  exit /b 0
)
call :resolve_active
call :pf_find "!DBX_PROFILE!"
if errorlevel 1 exit /b 0
set "_valid="
for %%i in (!_pf!) do (
  set "DBX_HOST=!PF_HOST_%%i!"
  set "DBX_ISDEFAULT=!PF_DEFAULT_%%i!"
  set "DBX_KIND=!PF_KIND_%%i!"
  set "_valid=!PF_VALID_%%i!"
)
set "DBX_STATE=OUT"
if not "!_valid!"=="true" exit /b 0
if "!DBX_KIND!"=="account" (
  set "DBX_STATE=IN"
  set "DBX_USER=account console profile"
  exit /b 0
)
call :dbx current-user me -p "!DBX_PROFILE!" -o json
if not "!DBX_RC!"=="0" exit /b 0
set "DBX_STATE=IN"
for /f "usebackq tokens=1,* delims=:" %%a in ("%OUTF%") do (
  set "_k=%%a"
  set "_k=!_k: =!"
  set "_k=!_k:"=!"
  if "!_k!"=="userName" (
    set "_v=%%b"
    call :clean_json_value
    set "DBX_USER=!_v!"
  )
)
if not defined DBX_USER set "DBX_USER=unknown user"
exit /b 0

rem ============================================================================
rem  SUBROUTINES - profiles
rem ============================================================================
:load_profiles
rem Fills PF_N and PF_NAME_i, PF_HOST_i, PF_VALID_i, PF_DEFAULT_i, PF_KIND_i
set "PF_N=0"
call :dbx auth profiles -o json
if not "!DBX_RC!"=="0" exit /b 1
set "_pn="
set "_ph="
set "_pv="
set "_pd="
for /f "usebackq tokens=1,* delims=:" %%a in ("%OUTF%") do (
  set "_k=%%a"
  set "_k=!_k: =!"
  set "_k=!_k:"=!"
  set "_v=%%b"
  if "!_k!"=="name" (
    call :clean_json_value
    set "_pn=!_v!"
  )
  if "!_k!"=="host" (
    call :clean_json_value
    set "_ph=!_v!"
  )
  if "!_k!"=="valid" (
    call :clean_json_value
    set "_pv=!_v!"
  )
  if "!_k!"=="default" (
    call :clean_json_value
    set "_pd=!_v!"
  )
  if "!_k:~0,1!"=="}" call :pf_emit
)
exit /b 0

:pf_emit
if not defined _pn exit /b 0
set /a PF_N+=1
if not defined _pv set "_pv=false"
if not defined _pd set "_pd=false"
set "PF_NAME_!PF_N!=!_pn!"
set "PF_HOST_!PF_N!=!_ph!"
set "PF_VALID_!PF_N!=!_pv!"
set "PF_DEFAULT_!PF_N!=!_pd!"
set "PF_KIND_!PF_N!=workspace"
if defined _ph if /i "!_ph:~0,17!"=="https://accounts." set "PF_KIND_!PF_N!=account"
set "_pn="
set "_ph="
set "_pv="
set "_pd="
exit /b 0

:pf_find
rem %1 = profile name -> _pf = its index, errorlevel 1 if not found
set "_pf="
for /l %%i in (1,1,!PF_N!) do if "!PF_NAME_%%i!"=="%~1" set "_pf=%%i"
if defined _pf exit /b 0
exit /b 1

:resolve_active
rem Keep the current profile if it still exists, otherwise pick one
if not defined DBX_PROFILE goto :resolve_pick
call :pf_find "!DBX_PROFILE!"
if not errorlevel 1 exit /b 0
:resolve_pick
set "DBX_PROFILE="
set "_saved="
if exist "%STATE_FILE%" set /p _saved=<"%STATE_FILE%"
if defined _saved call :pf_find "!_saved!"
if errorlevel 1 set "_saved="
set "_cli="
for /l %%i in (1,1,!PF_N!) do if "!PF_DEFAULT_%%i!"=="true" set "_cli=!PF_NAME_%%i!"
if "!SYNC_CLI_DEFAULT!"=="1" (
  if defined _cli (set "DBX_PROFILE=!_cli!") else if defined _saved set "DBX_PROFILE=!_saved!"
) else (
  if defined _saved (set "DBX_PROFILE=!_saved!") else if defined _cli set "DBX_PROFILE=!_cli!"
)
if defined DBX_PROFILE exit /b 0
call :pf_find "DEFAULT"
if not errorlevel 1 (
  set "DBX_PROFILE=DEFAULT"
  exit /b 0
)
set "DBX_PROFILE=!PF_NAME_1!"
exit /b 0

:set_active
rem %1 = profile name. Remembered by BrickBat and, with SYNC_CLI_DEFAULT=1, by the CLI
set "DBX_PROFILE=%~1"
(>"%STATE_FILE%" echo(!DBX_PROFILE!) 2>nul
if not "!SYNC_CLI_DEFAULT!"=="1" exit /b 0
call :dbx auth switch --profile "!DBX_PROFILE!"
exit /b 0

:normalize_host
rem Turns whatever was pasted into https://host
set "NEW_HOST=!NEW_HOST:"=!"
if not defined NEW_HOST exit /b 0
set "NEW_HOST=!NEW_HOST: =!"
if not defined NEW_HOST exit /b 0
set "_h=!NEW_HOST:*://=!"
set "_hh="
for /f "delims=#?/" %%h in ("!_h!") do set "_hh=%%h"
if not defined _hh (
  set "NEW_HOST="
  exit /b 0
)
set "NEW_HOST=https://!_hh!"
exit /b 0

:env_usable
rem %1 = profile index. errorlevel 0 when secrets can be read there
if "!PF_KIND_%~1!"=="account" exit /b 1
if "!PF_VALID_%~1!"=="true" exit /b 0
echo   !cDim!!PF_NAME_%~1! - skipped, not logged in!c0!
exit /b 1

rem ============================================================================
rem  SUBROUTINES - secrets data
rem ============================================================================
:load_scopes
rem %1 = profile -> SC_N, SC_NAME_i, SC_TYPE_i sorted by name
set "SC_N=0"
call :dbx secrets list-scopes -p "%~1"
if not "!DBX_RC!"=="0" exit /b 1
(
  for /f "usebackq tokens=1,2" %%a in ("%OUTF%") do (
    if not "%%a %%b"=="Scope Backend" echo(%%a %%b
  )
) > "%SORTF%"
sort "%SORTF%" /o "%NAMEF%"
for /f "usebackq tokens=1,2" %%a in ("%NAMEF%") do (
  set /a SC_N+=1
  set "SC_NAME_!SC_N!=%%a"
  set "SC_TYPE_!SC_N!=%%b"
)
exit /b 0

:load_secrets
rem %1 = profile, %2 = scope -> SE_N, SE_NAME_i, SE_TS_i sorted by key, or SE_ERR
set "SE_N=0"
set "SE_ERR="
call :dbx secrets list-secrets "%~2" -p "%~1"
if not "!DBX_RC!"=="0" (
  call :first_err SE_ERR
  exit /b 1
)
(
  for /f "usebackq tokens=1,2" %%a in ("%OUTF%") do (
    if not "%%a %%b"=="Key Last" echo(%%a %%b
  )
) > "%SORTF%"
sort "%SORTF%" /o "%NAMEF%"
for /f "usebackq tokens=1,2" %%a in ("%NAMEF%") do (
  set /a SE_N+=1
  set "SE_NAME_!SE_N!=%%a"
  set "SE_TS_!SE_N!=%%b"
)
exit /b 0

:load_acls
rem %1 = profile, %2 = scope -> AC_N, AC_PRIN_i, AC_PERM_i, or AC_ERR
set "AC_N=0"
set "AC_ERR="
call :dbx secrets list-acls "%~2" -p "%~1" -o json
if not "!DBX_RC!"=="0" (
  call :first_err AC_ERR
  exit /b 1
)
call :parse_acl_json
exit /b 0

:parse_acl_json
rem A principal is copied with delayed expansion off and read back with set /p, so ! and ^
rem in a name survive. The CLI's JSON writes & < > as \u0026 \u003c \u003e and \ as \\.
set "AC_N=0"
set "_ape="
set "_apr="
for /f "usebackq tokens=1,* delims=:" %%a in ("%OUTF%") do (
  set "_k=%%a"
  set "_k=!_k: =!"
  set "_k=!_k:"=!"
  if "!_k!"=="permission" (
    set "_v=%%b"
    call :clean_json_value
    set "_ape=!_v!"
  )
  if "!_k!"=="principal" (
    setlocal DisableDelayedExpansion
    >"%PRINF%" echo(%%b
    endlocal
    set "_v="
    <"%PRINF%" set /p "_v="
    call :clean_json_value
    if defined _v (
      set "_v=!_v:\u0026=&!"
      set "_v=!_v:\u003c=<!"
      set "_v=!_v:\u003e=>!"
      set "_v=!_v:\\=\!"
    )
    set "_apr=!_v!"
  )
  if "!_k:~0,1!"=="}" call :acl_emit
)
call :acl_emit
exit /b 0

:acl_emit
if not defined _apr exit /b 0
set /a AC_N+=1
set "AC_PRIN_!AC_N!=!_apr!"
set "AC_PERM_!AC_N!=!_ape!"
set "_apr="
set "_ape="
exit /b 0

:write_names
rem %1 = SC or SE -> writes the names of that list to NAMEF, one per line
(
  for /l %%i in (1,1,!%~1_N!) do echo(!%~1_NAME_%%i!
) > "%NAMEF%"
exit /b 0

rem ============================================================================
rem  SUBROUTINES - secrets display
rem ============================================================================
:list_add_env
rem %1 = profile index. Adds that environment's scopes whose name contains Q_SEARCH
call :env_usable %~1
if errorlevel 1 exit /b 0
if defined L_ONE goto :list_add_env_go
call :host_seen %~1
if not errorlevel 1 exit /b 0
:list_add_env_go
set "_p=!PF_NAME_%~1!"
call :load_scopes "!_p!"
if errorlevel 1 (
  call :first_err _e
  echo   !cErr!!_p! - !_e!!c0!
  exit /b 0
)
call :write_names SC
findstr /i /l /n /c:"!Q_SEARCH!" "%NAMEF%" > "%HITF%"
set "_hits=0"
for /f "usebackq tokens=1 delims=:" %%n in ("%HITF%") do (
  set /a L_N+=1, _hits+=1
  if not defined L_ONE set "L_PROF_!L_N!=!_p!"
  set "L_SCOPE_!L_N!=!SC_NAME_%%n!"
  set "L_TYPE_!L_N!=!SC_TYPE_%%n!"
)
echo   !_p! - !_hits! of !SC_N! scopes match
exit /b 0

:list_visible
rem VISF = numbers of the list entries whose name contains L_FILTER, V_N = how many
(
  for /l %%i in (1,1,!L_N!) do echo(!L_SCOPE_%%i!
) > "%NAMEF%"
if defined L_FILTER (
  findstr /i /l /n /c:"!L_FILTER!" "%NAMEF%" > "%HITF%"
) else (
  findstr /n /r /c:".*" "%NAMEF%" > "%HITF%"
)
set "V_N=0"
(
  for /f "usebackq tokens=1 delims=:" %%n in ("%HITF%") do (
    set /a V_N+=1
    echo(%%n
  )
) > "%VISF%"
exit /b 0

:list_print
for /f "usebackq delims=" %%n in ("%VISF%") do call :list_row %%n
exit /b 0

:list_row
rem %1 = list entry number
set "_num=    %~1"
set "_ty=Databricks"
if /i "!L_TYPE_%~1!"=="AZURE_KEYVAULT" set "_ty=Azure Key Vault"
set "_nm=!L_SCOPE_%~1!"
if "!_nm:~48!"=="" (
  set "_nm=!_nm!                                                "
  set "_nm=!_nm:~0,48!"
)
if defined L_ONE (
  echo  !cKey!!_num:~-4!!c0!  !_nm! !cDim!!_ty!!c0!
  exit /b 0
)
set "_pp=!L_PROF_%~1!"
if "!_pp:~14!"=="" (
  set "_pp=!_pp!              "
  set "_pp=!_pp:~0,14!"
)
echo  !cKey!!_num:~-4!!c0!  !_pp! !_nm! !cDim!!_ty!!c0!
exit /b 0

:list_get
rem %1 = list entry number -> SP, SCOPE and SCOPE_TYPE
set "SCOPE=!L_SCOPE_%~1!"
set "SCOPE_TYPE=!L_TYPE_%~1!"
if defined L_ONE (
  set "SP=!L_ONE!"
) else (
  set "SP=!L_PROF_%~1!"
)
exit /b 0

:print_secrets
if defined SE_ERR (
  echo   !cErr!  !SE_ERR!!c0!
  exit /b 0
)
if "!SE_N!"=="0" (
  echo   !cDim!  No secrets in this scope yet.!c0!
  exit /b 0
)
for /l %%i in (1,1,!SE_N!) do call :print_secret_row %%i
exit /b 0

:print_secret_row
call :ms_to_date "!SE_TS_%~1!"
set "_num=    %~1"
set "_nm=!SE_NAME_%~1!"
call :pad _nm 44
echo  !cKey!!_num:~-4!!c0!  !_nm! !cDim!!_date!!c0!
exit /b 0

:print_acls
if defined AC_ERR (
  echo   !cWarn!  !AC_ERR!!c0!
  if "!AC_ERR:does not exist=!"=="!AC_ERR!" (
    echo   !cDim!  Seeing and changing access needs MANAGE on the scope.!c0!
  ) else if defined SP_FAV (
    echo   !cDim!  Press S to remove it from your favourites.!c0!
  )
  exit /b 0
)
if "!AC_N!"=="0" (
  echo   !cDim!  No access entries.!c0!
  exit /b 0
)
for /l %%i in (1,1,!AC_N!) do call :print_acl_row %%i
exit /b 0

:print_acl_row
set "_num=    %~1"
set "_rp=!AC_PRIN_%~1!"
set "_tag="
call :is_guid "!_rp!"
if not errorlevel 1 set "_tag=  !cDim!service principal!c0!"
call :pad _rp 52
set "_rl=!AC_PERM_%~1!"
set "_rc=!cOk!"
if /i "!_rl!"=="WRITE" set "_rc=!cWarn!"
if /i "!_rl!"=="MANAGE" set "_rc=!cBrand!"
call :pad _rl 6
echo  !cKey!!_num:~-4!!c0!  !_rp! !_rc!!_rl!!c0!!_tag!
exit /b 0

:print_fav_row
set "_num=    %~1"
set "_ty="
if /i "!FAV_TYPE_%~1!"=="AZURE_KEYVAULT" set "_ty=  !cDim!Azure Key Vault!c0!"
echo  !cKey!!_num:~-4!!c0!  !FAV_SCOPE_%~1!!_ty!
exit /b 0

:bad_chars
rem %1 = variable name, %2 = extra allowed characters. errorlevel 0 when the value has a
rem character other than letters, digits, . _ - and %2, or starts with - (read as an
rem option by the CLI). eol is a delimiter, so no line is skipped as a comment.
if "!%~1:~0,1!"=="-" exit /b 0
for /f "eol=- delims=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-%~2" %%x in ("!%~1!") do exit /b 0
exit /b 1

:is_guid
rem %1 = text. errorlevel 0 when it looks like an application ID: 8-4-4-4-12 hex digits
set "_g=%~1"
if not defined _g exit /b 1
if not "!_g:~36!"=="" exit /b 1
if "!_g:~35,1!"=="" exit /b 1
if not "!_g:~8,1!!_g:~13,1!!_g:~18,1!!_g:~23,1!"=="----" exit /b 1
for /f "delims=0123456789abcdefABCDEF-" %%x in ("!_g!") do exit /b 1
exit /b 0

:print_match
set "_num=    %~1"
set "_mp=!M_PROF_%~1!"
call :pad _mp 14
set "_msc=!M_SCOPE_%~1!"
call :pad _msc 40
set "_mk="
if defined M_KEY_%~1 set "_mk=!cHead!!M_KEY_%~1!!c0!"
echo  !cKey!!_num:~-4!!c0!  !_mp! !_msc! !_mk!
exit /b 0

:ms_to_date
rem %1 = epoch milliseconds -> _date = YYYY-MM-DD HH:MM UTC
set "_date="
set "_ms=%~1"
if not defined _ms exit /b 0
for /f "delims=0123456789" %%x in ("!_ms!") do exit /b 0
if "!_ms:~0,-3!"=="" exit /b 0
set "_s=!_ms:~0,-3!"
:ms_strip
if "!_s:~0,1!"=="0" if not "!_s!"=="0" (
  set "_s=!_s:~1!"
  goto :ms_strip
)
set /a "_days=_s/86400, _sod=_s%%86400"
set /a "_z=_days+719468, _era=_z/146097, _doe=_z-_era*146097"
set /a "_yoe=(_doe-_doe/1460+_doe/36524-_doe/146096)/365"
set /a "_y=_yoe+_era*400, _doy=_doe-(365*_yoe+_yoe/4-_yoe/100)"
set /a "_mp=(5*_doy+2)/153"
set /a "_d=_doy-(153*_mp+2)/5+1, _m=_mp+3"
if !_m! gtr 12 set /a "_m-=12, _y+=1"
set /a "_hh=_sod/3600, _mi=_sod%%3600/60"
set "_m=0!_m!"
set "_d=0!_d!"
set "_hh=0!_hh!"
set "_mi=0!_mi!"
set "_date=!_y!-!_m:~-2!-!_d:~-2! !_hh:~-2!:!_mi:~-2! UTC"
exit /b 0

rem ============================================================================
rem  SUBROUTINES - looking inside a few scopes, comparing environments
rem ============================================================================
:lookup_one
rem %1 = list entry number. Looks for the key or the principal in that scope
set "_sc=!L_SCOPE_%~1!"
set "_sct=!L_TYPE_%~1!"
if defined L_ONE (
  set "_p=!L_ONE!"
) else (
  set "_p=!L_PROF_%~1!"
)
set /a _done+=1
if defined ESC (
  <nul set /p "=!ESC![1G!ESC![K   Checking !_done! of !V_N!:  !_p!  !_sc!"
) else (
  <nul set /p "=."
)
if "!LK_MODE!"=="acl" (
  call :lookup_acl
) else (
  call :lookup_key_in
)
exit /b 0

:lookup_acl
call :load_acls "!_p!" "!_sc!"
if errorlevel 1 (
  set "_e=!AC_ERR!"
  call :lookup_failed
  exit /b 0
)
for /l %%a in (1,1,!AC_N!) do if /i "!AC_PRIN_%%a!"=="!Q_PRIN!" call :lookup_hit "!AC_PERM_%%a!"
exit /b 0

:lookup_key_in
call :load_secrets "!_p!" "!_sc!"
if errorlevel 1 (
  set "_e=!SE_ERR!"
  call :lookup_failed
  exit /b 0
)
if "!SE_N!"=="0" exit /b 0
call :write_names SE
findstr /i /l /n /c:"!Q_SEARCH!" "%NAMEF%" > "%HITF%"
for /f "usebackq tokens=1 delims=:" %%n in ("%HITF%") do call :lookup_hit "!SE_NAME_%%n!"
exit /b 0

:lookup_hit
rem %1 = what to show after the scope - the permission or the key
set /a M_N+=1
set "M_PROF_!M_N!=!_p!"
set "M_SCOPE_!M_N!=!_sc!"
set "M_TYPE_!M_N!=!_sct!"
set "M_KEY_!M_N!=%~1"
exit /b 0

:lookup_failed
rem _e = error text. Permission problems are counted apart from other failures
set "_den="
if defined _e (
  if not "!_e:permission=!"=="!_e!" set "_den=1"
  if not "!_e:denied=!"=="!_e!" set "_den=1"
  if not "!_e:forbidden=!"=="!_e!" set "_den=1"
)
if defined _den (
  set /a LK_DENIED+=1
) else (
  set /a LK_FAILED+=1
)
exit /b 0

:compare_env
rem %1 = profile index. Lists the scopes there - one call - and shows keys and access
rem for every scope whose name is one of the variants - two calls per scope found
call :env_usable %~1
if errorlevel 1 exit /b 0
call :host_seen %~1
if not errorlevel 1 exit /b 0
set "_p=!PF_NAME_%~1!"
echo   !cHead!!_p!!c0!  !cDim!!PF_HOST_%~1!!c0!
call :load_scopes "!_p!"
if errorlevel 1 (
  call :first_err _e
  echo   !cErr!  !_e!!c0!
  echo(
  exit /b 0
)
call :write_names SC
set "_matches="
for /f "usebackq delims=" %%n in ("%NAMEF%") do if defined _C_%%n set "_matches=!_matches! %%n"
if defined _matches goto :compare_env_found
echo   !cDim!  No matching scope here.!c0!
echo(
exit /b 0
:compare_env_found
for %%m in (!_matches!) do call :compare_show "%%m"
exit /b 0

:compare_show
rem %1 = scope name in environment _p. Shows its keys and access - two calls
echo   !cDim!  Scope  !c0!!cHead!%~1!c0!
call :load_secrets "!_p!" "%~1"
echo   !cDim!  Keys!c0!
call :print_secrets
call :load_acls "!_p!" "%~1"
echo   !cDim!  Access!c0!
call :print_acls
echo(
exit /b 0

:scope_variants
rem %1 = scope name. Marks _C_name for the name itself and for every name it has when
rem an environment word in it - between dots, underscores or dashes - is swapped for
rem another word in ENV_WORDS. VAR_PAT = the name with that word shown as *
set "VAR_PAT="
set "VAR_LIST="
set "_x=.%~1."
call :add_variant "%~1"
for %%w in (!ENV_WORDS!) do for %%l in (. _ -) do for %%r in (. _ -) do call :scope_variants_of "%%l%%w%%r" "%%l" "%%r"
exit /b 0

:scope_variants_of
rem %1 = an environment word with a character on each side, %2 and %3 = those characters.
rem When the name contains it, adds the name with the word swapped for every ENV_WORDS word
set "_t=!_x:%~1=!"
if "!_t!"=="!_x!" exit /b 0
for %%v in (!ENV_WORDS!) do (
  set "_y=!_x:%~1=%~2%%v%~3!"
  call :add_variant "!_y:~1,-1!"
)
if defined VAR_PAT exit /b 0
set "_y=!_x:%~1=%~2*%~3!"
set "VAR_PAT=!_y:~1,-1!"
exit /b 0

:add_variant
rem %1 = a scope name to look for in every environment
if defined _C_%~1 exit /b 0
set "_C_%~1=1"
set "VAR_LIST=!VAR_LIST! %~1"
exit /b 0

:clear_variants
for %%c in (!VAR_LIST!) do set "_C_%%c="
set "VAR_LIST="
exit /b 0

:host_seen
rem %1 = profile index. errorlevel 0 when a profile for the same workspace was already
rem handled in this round (start a round with _seen=|), else remembers it: errorlevel 1
set "_hh=!PF_HOST_%~1!"
if not defined _hh exit /b 1
if "!_hh:~-1!"=="/" set "_hh=!_hh:~0,-1!"
if not "!_seen:|%_hh%|=!"=="!_seen!" exit /b 0
set "_seen=!_seen!!_hh!|"
exit /b 1

rem ============================================================================
rem  SUBROUTINES - favourites
rem  favourites.txt in STATE_DIR holds one line per favourite: workspace URL,
rem  scope name and backend type, separated by spaces. Scope names have none.
rem ============================================================================
:fav_host
rem %1 = workspace URL -> _fh = the same URL without a trailing slash
set "_fh=%~1"
if not defined _fh exit /b 0
if "!_fh:~-1!"=="/" set "_fh=!_fh:~0,-1!"
exit /b 0

:load_favs
rem Favourites of the active workspace -> FAV_N, FAV_SCOPE_i, FAV_TYPE_i
set "FAV_N=0"
if not defined DBX_HOST exit /b 0
if not exist "%FAV_FILE%" exit /b 0
call :fav_host "!DBX_HOST!"
for /f "usebackq tokens=1,2,3" %%a in ("%FAV_FILE%") do (
  if /i "%%a"=="!_fh!" (
    set /a FAV_N+=1
    set "FAV_SCOPE_!FAV_N!=%%b"
    set "FAV_TYPE_!FAV_N!=%%c"
  )
)
exit /b 0

:is_fav
rem %1 = workspace URL, %2 = scope. errorlevel 0 when the scope is a favourite there
if not exist "%FAV_FILE%" exit /b 1
call :fav_host "%~1"
if not defined _fh exit /b 1
for /f "usebackq tokens=1,2" %%a in ("%FAV_FILE%") do if /i "%%a"=="!_fh!" if "%%b"=="%~2" exit /b 0
exit /b 1

:fav_remove
rem %1 = workspace URL without a trailing slash, %2 = scope. Removes that favourite
if not exist "%FAV_FILE%" exit /b 0
(
  for /f "usebackq tokens=1,2,3" %%a in ("%FAV_FILE%") do (
    set "_keep=1"
    if /i "%%a"=="%~1" if "%%b"=="%~2" set "_keep="
    if defined _keep echo(%%a %%b %%c
  )
) > "%FAVTMP%"
move /y "%FAVTMP%" "%FAV_FILE%" >nul 2>&1
exit /b 0

rem ============================================================================
rem  SUBROUTINES - running the CLI, input and output helpers
rem ============================================================================
:dbx
rem Runs databricks with the given arguments. stdout to OUTF, stderr to ERRF,
rem exit code in DBX_RC. NO_COLOR keeps colour codes out of the captured output.
set "_nc=!NO_COLOR!"
set "NO_COLOR=1"
databricks %* >"%OUTF%" 2>"%ERRF%"
set "DBX_RC=!errorlevel!"
if defined _nc (set "NO_COLOR=!_nc!") else (set "NO_COLOR=")
exit /b !DBX_RC!

:typed_intro
rem Clears stray keys and says how to paste. _flush = leftover keys from a paste with line
rem breaks can be dropped after each value - not where PowerShell is blocked
set "_flush=1"
powershell -NoProfile -NonInteractive -Command "$Host.UI.RawUI.FlushInputBuffer()" >nul 2>&1 || set "_flush="
echo   !cDim!The CLI asks for the value now. Paste with right-click or Ctrl+V, then press Enter.!c0!
if defined _flush (
  echo   !cDim!One line only. For a value with line breaks, use F instead.!c0!
) else (
  echo   !cWarn!One line only. A paste with line breaks would leave the rest as keystrokes for the next prompts here - use F for those.!c0!
)
exit /b 0

:put_typed
rem SCOPE, KEY, SP -> _rc. The CLI asks for the value itself, hidden - BrickBat never sees it.
rem It hides the value only where it may use colours: with NO_COLOR, TERM=dumb or Git Bash
rem it reads the console in clear instead, so those are cleared for this call. The log
rem level is pinned too, because debug logging would print the value.
setlocal
set "NO_COLOR="
if /i "!TERM!"=="dumb" set "TERM="
set "MSYSTEM="
databricks secrets put-secret "!SCOPE!" "!KEY!" -p "!SP!" --log-level error
endlocal & set "_rc=%errorlevel%"
rem Drop keys left over from a paste with line breaks, so they can't reach the next prompts
if defined _flush powershell -NoProfile -NonInteractive -Command "$Host.UI.RawUI.FlushInputBuffer()" >nul 2>&1
exit /b 0

:clear_clipboard
rem A pipe, not <nul: clip takes NUL for console input and leaves the clipboard as it is
type nul | clip >nul 2>&1
if errorlevel 1 exit /b 0
echo(
echo   !cDim!BrickBat emptied the clipboard. If clipboard history is on, delete the value in Win+V too.!c0!
exit /b 0

:ask_value_file
rem Asks for the file that holds the value and checks it -> VFILE. errorlevel 1 = back
echo   !cDim!The file is sent exactly as saved, so a line break at the end becomes part of the secret.!c0!
set "VFILE="
set /p "VFILE=!c0!   Path to the file - you can drag the file into this window: "
if not defined VFILE exit /b 1
set "VFILE=!VFILE:"=!"
call :trim_var VFILE
if not defined VFILE exit /b 1
if not exist "!VFILE!" (
  echo   !cErr!File not found: !VFILE!!c0!
  call :pause_any
  exit /b 1
)
if exist "!VFILE!\" (
  echo   !cErr!That is a folder, not a file: !VFILE!!c0!
  call :pause_any
  exit /b 1
)
rem Check the bytes in memory, without showing them. The path reaches PowerShell through
rem the environment, so no part of it is read as code.
set "_vf="
for /f %%r in ('powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop';$b=[IO.File]::ReadAllBytes($env:VFILE);$n=$b.Length;$f='.';if($n -eq 0){$f+='E'};if($n -ge 2 -and $b[0]+$b[1] -eq 509){$f+='U'};if($n -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191){$f+='B'};if($n -gt 0 -and $b[$n-1] -eq 10){$f+='N'};$f" 2^>nul') do set "_vf=%%r"
if not defined _vf echo   !cDim!BrickBat could not check this file - make sure it has no line break at the end.!c0!
if defined _vf if not "!_vf!"=="." (
  if not "!_vf:E=!"=="!_vf!" echo   !cWarn!The file is empty.!c0!
  if not "!_vf:U=!"=="!_vf!" echo   !cWarn!The file is UTF-16 - save it as UTF-8 first, or the secret is stored as UTF-16.!c0!
  if not "!_vf:B=!"=="!_vf!" echo   !cWarn!The file starts with a byte-order mark - it becomes part of the secret.!c0!
  if not "!_vf:N=!"=="!_vf!" echo   !cWarn!The file ends with a line break - it becomes part of the secret. Fine for JSON or PEM, wrong for a password or token.!c0!
  call :confirm
  if not defined CONFIRMED exit /b 1
)
exit /b 0

:acl_state
rem AC_* of a scope and PRIN -> _cur = PRIN's permission there (empty if none), _mg = how
rem many MANAGE entries the scope has
set "_cur="
set "_mg=0"
for /l %%i in (1,1,!AC_N!) do (
  if "!AC_PERM_%%i!"=="MANAGE" set /a _mg+=1
  if /i "!AC_PRIN_%%i!"=="!PRIN!" set "_cur=!AC_PERM_%%i!"
)
exit /b 0

:acl_apply
rem SCOPE, SP, PRIN, PERM and _cur from :acl_state -> DBX_RC. Replacing an entry means delete,
rem then put. Never for MANAGE: if the put failed, nobody might be left with MANAGE
set "DBX_ARGS=secrets put-acl "!SCOPE!" "!PRIN!" !PERM! -p "!SP!""
call :dbx_args
if "!DBX_RC!"=="0" exit /b 0
findstr /i /c:"ALREADY_EXISTS" /c:"already exists" "%ERRF%" >nul 2>&1
if errorlevel 1 exit /b 0
if "!_cur!"=="MANAGE" (
  echo(
  if /i "!PRIN!"=="!DBX_USER!" (
    echo   !cWarn!You have MANAGE now. Another MANAGE holder or a workspace admin has to change your entry.!c0!
  ) else echo   !cWarn!!PRIN! has MANAGE now. Remove it with X first, then grant !PERM!.!c0!
  exit /b 0
)
set "DBX_ARGS=secrets delete-acl "!SCOPE!" "!PRIN!" -p "!SP!""
call :dbx_args
if not "!DBX_RC!"=="0" exit /b 0
set "DBX_ARGS=secrets put-acl "!SCOPE!" "!PRIN!" !PERM! -p "!SP!""
call :dbx_args
if not "!DBX_RC!"=="0" echo   !cErr!The old access for !PRIN! was removed, but !PERM! could not be set.!c0!
exit /b 0

:dbx_args
rem Like :dbx, with the arguments in DBX_ARGS. They are expanded once and never parsed
rem again, so ! ^ % & in a principal reach the CLI exactly as shown on screen
set "_nc=!NO_COLOR!"
set "NO_COLOR=1"
databricks !DBX_ARGS! >"%OUTF%" 2>"%ERRF%"
set "DBX_RC=!errorlevel!"
if defined _nc (set "NO_COLOR=!_nc!") else (set "NO_COLOR=")
exit /b !DBX_RC!

:clean_json_value
rem Strips quotes, surrounding spaces and a trailing comma from _v
if not defined _v exit /b 0
set "_v=!_v:"=!"
:clean_json_lead
if not defined _v exit /b 0
if "!_v:~0,1!"==" " (
  set "_v=!_v:~1!"
  goto :clean_json_lead
)
if "!_v:~-1!"=="," set "_v=!_v:~0,-1!"
:clean_json_trim
if not defined _v exit /b 0
if "!_v:~-1!"==" " (
  set "_v=!_v:~0,-1!"
  goto :clean_json_trim
)
exit /b 0

:first_err
rem %1 = variable that receives the most useful line of ERRF
set "%~1="
for /f "usebackq delims=" %%e in (`findstr /b /c:"Error:" "%ERRF%" 2^>nul`) do if not defined %~1 set "%~1=%%e"
if not defined %~1 for /f "usebackq delims=" %%e in ("%ERRF%") do if not defined %~1 set "%~1=%%e"
if not defined %~1 set "%~1=The command failed without an error message."
exit /b 0

:show_err
call :first_err _e
echo   !cErr!!_e!!c0!
findstr /i /c:"PERMISSION_DENIED" /c:"does not have" /c:"not authorized" "%ERRF%" >nul 2>&1
if not errorlevel 1 echo   !cDim!Your user is missing a permission for this. Access changes need MANAGE, secret changes WRITE.!c0!
findstr /i /c:"refresh token" /c:"invalid_grant" /c:"auth login" /c:"default credentials" "%ERRF%" >nul 2>&1
if not errorlevel 1 echo   !cDim!The login for this profile is missing or expired. Log in again from the front page.!c0!
exit /b 0

:report
rem Reports the last dbx call: MSG in green on success, the error otherwise
echo(
if not "!DBX_RC!"=="0" goto :report_err
echo   !cOk!!MSG!!c0!
call :pause_any
exit /b 0
:report_err
call :show_err
call :pause_any
exit /b 1

:menu
rem %1 = allowed keys -> MENU_KEY = the key that was pressed
set "MENU_KEY="
set "_keys=%~1"
choice /c !_keys! /n /m "!c0!   Choose: "
set /a "_i=!errorlevel!-1"
if !_i! lss 0 exit /b 0
set "MENU_KEY=!_keys:~%_i%,1!"
exit /b 0

:pause_any
echo(
<nul set /p "=!cDim!   Press any key to continue...!c0!"
pause >nul
echo(
exit /b 0

:confirm
set "CONFIRMED="
choice /c YN /n /m "!c0!   Are you sure? [Y/N] "
if "!errorlevel!"=="1" set "CONFIRMED=1"
exit /b 0

:pick_number
rem %1 = highest number, %2 = prompt -> PICK = chosen number, empty when cancelled
set "PICK="
set "_in="
set /p "_in=!c0!%~2"
if not defined _in exit /b 0
set "_in=!_in:"=!"
call :is_index "!_in!" %~1
exit /b 0

:is_index
rem %1 = text, %2 = highest number -> PICK = the number when text is 1..%2
set "PICK="
set "_x=%~1"
if not defined _x exit /b 0
set "_x=!_x: =!"
if not defined _x exit /b 0
for /l %%i in (1,1,%~2) do if "!_x!"=="%%i" set "PICK=%%i"
exit /b 0

:pad
rem %1 = variable name, %2 = width up to 64. Pads with spaces, never cuts the value
if not "!%~1:~%~2!"=="" exit /b 0
set "%~1=!%~1!                                                                "
set "%~1=!%~1:~0,%~2!"
exit /b 0

:trim_var
rem %1 = variable name -> leading and trailing spaces removed
:trim_var_lead
if not defined %~1 exit /b 0
if "!%~1:~0,1!"==" " (
  set "%~1=!%~1:~1!"
  goto :trim_var_lead
)
:trim_var_loop
if not defined %~1 exit /b 0
if "!%~1:~-1!"==" " (
  set "%~1=!%~1:~0,-1!"
  goto :trim_var_loop
)
exit /b 0

rem ============================================================================
rem  NO CLI / OLD CLI / QUIT
rem ============================================================================
:no_cli
cls
call :banner
echo(
echo   !cErr!The Databricks CLI was not found on this PC.!c0!
echo(
echo   !cKey![Y]!c0! Install it now with winget     !cKey![Q]!c0! Quit
echo(
call :menu YQ
if not "!MENU_KEY!"=="Y" goto :quit
winget install --id Databricks.DatabricksCLI -e
set "_rc=!errorlevel!"
rem 0x8A15002B: no newer version - the CLI is already installed, this window just can't see it
if "!_rc!"=="-1978335189" set "_rc=0"
echo(
if "!_rc!"=="0" (
  echo   !cOk!Done.!c0! Start BrickBat again in a new window so it can find the CLI.
) else (
  echo   !cErr!The install did not finish - see the message above.!c0!
)
call :pause_any
goto :quit

:legacy_cli
cls
call :banner
echo(
echo   !cWarn!This looks like the old Python Databricks CLI: !CLI_VER!!c0!
echo   BrickBat needs the new Databricks CLI. Remove the old one with:
echo(
echo       pip uninstall databricks-cli
echo(
echo   then start BrickBat again - it offers to install the new CLI if it is missing.
call :pause_any
goto :quit

:quit
del "%OUTF%" "%ERRF%" "%NAMEF%" "%HITF%" "%SORTF%" "%VISF%" "%FAVTMP%" "%PRINF%" >nul 2>&1
if defined ORIG_CP chcp !ORIG_CP! >nul
endlocal
exit /b 0
