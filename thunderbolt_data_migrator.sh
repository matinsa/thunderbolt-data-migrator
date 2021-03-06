#!/bin/bash

# Written by Ryan Ball
# Updated by Matin Sasaluxanon
version=00.00.05
# Version History:
#         2021-06-09 - 00.00.05
#           * fixed rsync to allow for commenting options if needed
#         2021-05-03 - 00.00.04
#           * fix prompt for entire home directory or date only
#           * added prompt variable to jamfhelper call
#           * fix rsync multi line command.  macOS 10.15.7 running into issues with comments
#         2021-04-28 - 00.00.03
#           * added prompt for user to decide if user would like to transfer data only or entire home directory during this process
#         2020-12-14 - 0.2
#           * Updated rsync --exclude
#             * '.localized'
#             * 'Dropbox'
#             * added exclusions for icloud account login issues
#             * added exclusions to not transfer over recent ms office open files list
#             * Folders to Exclude
#               * logs
#               * ByHost
#               * iCloud Drive
#               * Accounts
#
#         2020-12-10 - 0.1
#           * Updated icon location for 10.15
#           * determine thunderbold mount drive on 10.15
#           * add - check external file locations
#           * updated initial message from a few seconds to until you see the symbols floating on the screen
#
#
#
# Reference
# - Originally obtained from: https://github.com/ryangball/thunderbolt-data-migrator
# - https://phoenixnap.com/kb/rsync-exclude-files-and-directories
# - https://stackoverflow.com/questions/2609552/how-can-i-use-as-an-awk-field-separator
# - https://gist.github.com/artifactsauce/1332529
# - https://www.systutorials.com/how-to-add-inline-comments-for-multi-line-command-in-bash-script/
# - https://stackoverflow.com/questions/58416663/how-do-i-set-a-variable-with-the-output-of-rsync-while-keeping-the-format

# This variable can be used if you are testing the script
# Set to true while testing, the rsync will be bypassed and nothing permanent will done to this Mac
# Set to false when used in production
#testing="true"  # (true|false)
testing="false"  # (true|false)

# The full path of the log file
log="/Library/Logs/thunderbolt_data_migration.log"

# The main icon displayed in jamfHelper dialogs
if [[ -e "/Applications/Utilities/Migration Assistant.app/Contents/Resources/MigrateAsst.icns" ]]; then
    # 10.14 and below
    icon="/Applications/Utilities/Migration Assistant.app/Contents/Resources/MigrateAsst.icns"
  elif [[ -e "/System/Applications/Utilities/Migration Assistant.app/Contents/Resources/MigrateAsst.icns" ]];then
    # 10.15
    icon="/System/Applications/Utilities/Migration Assistant.app/Contents/Resources/MigrateAsst.icns"
  else
    icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarCustomizeIcon.icns"
fi

# The instructions that are shown in the first dialog to the user
instructions="You can now migrate your data from your old Mac.

1. Turn your old Mac off.

2. Connect your old Mac and new Mac together using the supplied Thunderbolt cable.

3. Power on your old Mac by normally pressing the power button WHILE holding the \"T\" button down til you see the USB/Thunderbolt Symbols floating on the screen.

We will attempt to automatically detect your old Mac now..."

###### Variables below this point are not intended to be modified ######
scriptName=$(basename "$0")
jamfHelper=/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper

os_version=$(sw_vers -productVersion | awk  -F  "." '{print $1}')
os_major_release=$(sw_vers -productVersion | awk  -F  "." '{print $2}')
os_minor_release=$(sw_vers -productVersion | awk  -F  "." '{print $3}')

function writelog () {
    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    /bin/echo "${1}"
    /bin/echo "$DATE" " $1" >> "$log"
}

function finish () {
    writelog "======== Finished $scriptName ========"
    ps -p "$jamfHelperPID" > /dev/null && kill "$jamfHelperPID"; wait "$jamfHelperPID" 2>/dev/null
    rm /tmp/output.txt
    exit "$1"
}

function wait_for_gui () {
    # Wait for the Dock to determine the current user
    DOCK_STATUS=$(pgrep -x Dock)
    writelog "Waiting for Desktop..."

    while [[ "$DOCK_STATUS" == "" ]]; do
        writelog "Desktop is not loaded; waiting..."
        sleep 5
        DOCK_STATUS=$(pgrep -x Dock)
    done

    loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
    writelog "$loggedInUser is logged in and at the desktop; continuing."
}

function wait_for_jamfHelper () {
    # Make sure jamfHelper has been installed
    writelog "Waiting for jamfHelper to be installed..."
    while [[ ! -e "$jamfHelper" ]]; do
        sleep 2
    done
    writelog "jamfHelper detected; continuing."
}

function perform_rsync () {
    # Prompt user to click transfer entire home directory or just data
    promptMessage="Would you like to transfer your entire home directory or just the data in your home directory?"
    promptChoice1="Entire Home Directory"
    promptChoice2="Data Only"
    prompt=$( /usr/bin/osascript -e "display dialog \"$promptMessage\" buttons {\"$promptChoice1\", \"$promptChoice2\"}" | awk -F: {'print $2'} )
    #writelog "--> prompt=$prompt"

    writelog "Beginning rsync transfer..."
    "$jamfHelper" -windowType fs -title "" -icon "$icon" -heading "Please wait as we transfer your $prompt to your new Mac..." \
        -description "This might take a few minutes. Once the transfer is complete this screen will close." &>/dev/null &
    jamfHelperPID=$(/bin/echo $!)

    #writelog "--> testing=$testing"
    #writelog "--> prompt=$prompt"

	DIR_TMP=/var/tmp/output.txt

    if [[ "$testing" != "true" ]]; then
      if [[ "$prompt" = "button returned:Entire Home Directory" ]] || [[ "$prompt" = "Entire Home Directory" ]]; then
      	writelog "--> Entire Home Directory Only"
        ####### Perform the rsync####################################################

        cmd_options=(
          # INSTRUCTIONS: Use Comments to disable option in the array if needed
          -vrpog
          --progress
          --update
          --ignore-errors
          --force
          # Hidden Files or Folders
          --exclude='.Trash'
          --exclude='.DS_Store'
          --exclude='.localized'
          # Folders
          --exclude='Logs'
          --exclude='ByHost'
          --exclude="/Dropbox/"
          --exclude="/iCloud Drive/"
          --exclude="/Library/Application Support/iCloud/Accounts/"
          --exclude="/Library/Accounts/"
          # Files
          --exclude="com.microsoft.Word.securebookmarks.plist"
          --exclude="com.microsoft.Excel.securebookmarks.plist"
          --exclude="com.microsoft.PowerPoint.securebookmarks.plist"
          --exclude="MobileMeAccounts.plist"
          # Log
          --log-file="$log"
        )
        /usr/bin/rsync "${cmd_options[@]}" "$oldUserHome/" "/Users/$loggedInUser/" >> $DIR_TMP

        ##############################################################################
      elif [[ "$prompt" = "button returned:Data Only" ]] || [[ "$prompt" = "Data Only" ]]; then
	      writelog "--> Data Only"
        ####### Perform the rsync####################################################

        cmd_options=(
          # INSTRUCTIONS: Use Comments to disable option in the array if needed
          -vrpog
          --progress
          --update
          --ignore-errors
          --force
          # Hidden Files or Folders
          --exclude='.Trash'
          --exclude='.DS_Store'
          --exclude='.localized'
          # Folders
          --exclude='Library'
          # Log
          --log-file="$log"
        )
        /usr/bin/rsync "${cmd_options[@]}" "$oldUserHome/" "/Users/$loggedInUser/" >> $DIR_TMP

        ##############################################################################
      fi
      # Ensure permissions are correct
      /usr/sbin/chown -R "$loggedInUser" "/Users/$loggedInUser" 2>/dev/null

	OUTPUT=$(cat $DIR_TMP)
	rm $DIR_TMP
    else
        writelog "Sleeping for 10 to simulate rsync..."
        sleep 10
    fi

    ps -p "$jamfHelperPID" > /dev/null && kill "$jamfHelperPID"; wait "$jamfHelperPID" 2>/dev/null
    writelog "Finished rsync transfer."
    sleep 3
    echo -e "$OUTPUT"
    /usr/sbin/diskutil unmount "/Volumes/$tBoltVolume" &>/dev/null
    finish 0
}

function calculate_space_requirements () {
    # Determine free space on this Mac
    freeOnNewMac=$(df -k / | tail -n +2 | awk '{print $4}')
    writelog "Free space on this Mac: $freeOnNewMac KB ($((freeOnNewMac/1024)) MB)"

    # Determine how much space the old home folder takes up
    spaceRequired=$(du -sck "$oldUserHome" | grep total | awk '{print $1}')
    writelog "Storage requirements for \"$oldUserHome\": $spaceRequired KB ($((spaceRequired/1024)) MB)"

    if [[ "$freeOnNewMac" -gt "$spaceRequired" ]]; then
        writelog "There is more than $spaceRequired KB available on this Mac; continuing."
        perform_rsync
    else
        writelog "Not enough free space on this Mac; exiting."
        "$jamfHelper" -windowType utility -title "User Data Transfer" -icon "$icon" -description "Your new Mac does not have enough free space to transfer your old data over. If you want to try again, please contact the Help Desk." -button1 "OK" -calcelButton "1" -defaultButton "1" &>/dev/null &
        finish 1
    fi
}

function manually_find_old_user () {
    # Determine all home folders on the old Mac
    oldUsersArray=()
    while IFS='' read -ra line; do oldUsersArray+=("$line"); done < <(/usr/bin/find "/Volumes/$tBoltVolume/Users" -maxdepth 1 -mindepth 1 -type d | awk -F'/' '{print $NF}' | grep -v Shared)

    # Exit if we didn't find any users
    if [[ "${#oldUsersArray[@]}" -eq 0 ]]; then
        echo "No user home folders found in: /Volumes/$tBoltVolume/Users"
        "$jamfHelper" -windowType utility -title "User Data Transfer" -icon "$icon" -description "Could not find any user home folders on the selected Thunderbolt volume. If you have any questions, please contact the Help Desk." -button1 "OK" -calcelButton "1" -defaultButton "1" &>/dev/null &
        finish 1
    fi

    # Show list of home folders so that the user can choose their old username
    # Something like cocoadialog would be preferred here as it has a dropdown, but it's got no Dark Mode :(
    # Heredocs cause some weird allignment issues
dialogOutput=$(/usr/bin/osascript <<EOF
    set ASlist to the paragraphs of "$(printf '%s\n' "${oldUsersArray[@]}")"
    choose from list ASlist with title "User Data Transfer" with prompt "Please choose your user account from your old Mac."
EOF
)

    # If the user chose one, store that as a variable, then see if we have enough space for the old data
    dialogOutput=$(grep -v "false" <<< "$dialogOutput")
    if [[ -n "$dialogOutput" ]]; then
        oldUserName="$dialogOutput"
        oldUserHome="/Volumes/$tBoltVolume/Users/$oldUserName"
        calculate_space_requirements
    else
        writelog "User cancelled; exiting."
        finish 0
    fi
}

function auto_find_old_user () {
    # Automatically loop through the user accounts on the old Mac, if one is found that matches the currently logged in user
    # we assume that is the user account to transfer data from. If a matching user is not found, let them manually chooose.
    while read -r line; do
        if [[ "$line" == "$loggedInUser" ]]; then
            writelog "Found a matching user ($line) on the chosen Thunderbolt volume; continuing."
            oldUserName="$line"
            oldUserHome="/Volumes/$tBoltVolume/Users/$line"
            calculate_space_requirements
        fi
    done < <(/usr/bin/find "/Volumes/$tBoltVolume/Users" -maxdepth 1 -mindepth 1 -type d | awk -F'/' '{print $NF}' | grep -v Shared)
    writelog "User with matching name on old Mac not found, moving on to manual selection."
    manually_find_old_user
}

function choose_tbolt_volume () {
    # Figure out all connected Thunderbolt volumes
    tboltVolumesArray=()
    while IFS='' read -ra line; do
        while IFS='' read -ra line; do tboltVolumesArray+=("$line"); done < <(diskutil info "$line" | grep -B15 "Thunderbolt" | grep "Mount Point" | sed -n -e 's/^.*Volumes\///p')
    done < <(system_profiler SPStorageDataType | grep "BSD Name" | awk '{print $NF}' | sort -u)

    # Exit if we didn't find any connected Thunderbolt volumes
    if [[ "${#tboltVolumesArray[@]}" -eq 0 ]]; then
        writelog "No Thunderbolt volumes connected at this time; exiting."
        "$jamfHelper" -windowType utility -title "User Data Transfer" -icon "$icon" -description "There are no Thunderbolt volumes attached at this time. If you want to try again, please contact the Help Desk." -button1 "OK" -calcelButton "1" -defaultButton "1" &>/dev/null &
        finish 1
    fi

    # Allow the user to choose from a list of connected Thunderbolt volumes
    # Something like cocoadialog would be preferred here as it has a dropdown, but it's got no Dark Mode :(
    # Heredocs cause some weird allignment issues
dialogOutput=$(/usr/bin/osascript <<EOF
    set ASlist to the paragraphs of "$(printf '%s\n' "${tboltVolumesArray[@]}")"
    choose from list ASlist with title "User Data Transfer" with prompt "Please choose the Thunderbolt volume to transfer your data from."
EOF
)

    # If the user chose one, store that as a variable
    dialogOutput=$(grep -v "false" <<< "$dialogOutput")
    if [[ -n "$dialogOutput" ]]; then
        tBoltVolume="$dialogOutput"
        writelog "\"/Volumes/$tBoltVolume\" was selected by the user."
        auto_find_old_user
    else
        writelog "User cancelled; exiting"
        finish 0
    fi
}

function detect_new_tbolt_volumes () {
    # Automaticaly detect a newly added Thunderbolt volume. The timer variable below can be modified to fit your environment
    # Most of this function (in the while loop) will loop every two seconds until the timer is done
    local timer="120"
    writelog "Waiting for Thuderbolt volumes..."
    while [[ "$timer" -gt "0" ]]; do
        # Determine status of jamfHelper
        if [[ "$(cat /tmp/output.txt)" == "0" ]]; then
            writelog "User cancelled; exiting."
            finish 0
        elif [[ "$(cat /tmp/output.txt)" == "2" ]]; then
            writelog "User chose to select a volume themselves."
            while [[ -z "$tBoltVolume" ]]; do
                choose_tbolt_volume
            done
            return
        fi

        # Get the mounted volumes once (before)
        diskListBefore=$(/sbin/mount | grep '/dev/' | grep '/Volumes' | awk '{print $1}')
        diskCountBefore=$(echo -n "$diskListBefore" | grep -c '^')  # This method will produce a 0 if none, where as wc -l will not
        sleep 5

        # Get the mounted volumes 2 seconds later (after)
        diskListAfter=$(/sbin/mount | grep '/dev/' | grep '/Volumes' | awk '{print $1}')
        diskCountAfter=$(echo -n "$diskListAfter" | grep -c '^')  # This method will produce a 0 if none, where as wc -l will not

        # Determine if an additional volume has been mounted since our first check, if so we will check to see if it is Thunderbolt
        # If so, we move on to find the user accounts on the newly connected Thunderbolt volume
        # If not we ignore the newly connected non-Thunderbolt volume
        # for 10.14 and below
        additional_opt1=$(/usr/bin/comm -13 <(echo "$diskListBefore") <(echo "$diskListAfter"))
        # 10.15
        additional_opt2=$(/usr/bin/comm -13 <(echo "$diskListBefore") <(echo "$diskListAfter") | tr '\n' ' ' | awk '{print $1}')

        if [[ "$diskCountBefore" -lt "$diskCountAfter" ]]; then
            if [[ $os_version == "11" ]]; then
              additional=$additional_opt2
            elif [[ $os_version == "10" ]]; then
              if [[ $os_major_release == "15" ]]; then
                additional=$additional_opt2
              elif [[ $os_major_release == "14" ]]; then
                additional=$additional_opt1
              elif [[ $os_major_release == "13" ]]; then
                additional=$additional_opt1
              else
                additional=$additional_opt1
              fi
            else
            additional=$additional_opt2
        fi
        isTBolt=$(/usr/sbin/diskutil info "$additional" | grep -B15 "Thunderbolt" | grep "Mount Point" | sed -n -e 's/^.*Volumes\///p')
          if [[ -n "$isTBolt" ]]; then
              tBoltVolume="$isTBolt"
              writelog "\"/Volumes/$tBoltVolume\" has been detected as a new Thunderbolt volume; continuing."
              ps -p "$jamfHelperPID" > /dev/null && kill "$jamfHelperPID"; wait "$jamfHelperPID" 2>/dev/null
              auto_find_old_user
          fi
      fi
      timer=$((timer-5))
    done
    # At this point the timer has run out, kill the background jamfHelper dialog and let the user know
    ps -p "$jamfHelperPID" > /dev/null && kill "$jamfHelperPID"; wait "$jamfHelperPID" 2>/dev/null
    writelog "Unable to detect a Thunderbolt volume in the amount of time specified; exiting."
    "$jamfHelper" -windowType utility -title "User Data Transfer" -icon "$icon" -description "We were unable to detect your old Mac. If you want to try again, please contact the Help Desk." -button1 "OK" -calcelButton "1" -defaultButton "1" &>/dev/null &
    finish 1
}

writelog " "
writelog "======== Starting $scriptName ========"
writelog "Version: $version "
writelog " "

# Wait for a GUI
wait_for_gui

# Wait for jamfHelper to be installed
wait_for_jamfHelper

# Display a jamfHelper dialog with instructions as a background task
"$jamfHelper" -windowType utility -title "User Data Transfer" -icon "$icon" -description "$instructions" -button1 "Cancel" -button2 "I'll Pick" -calcelButton "1" -defaultButton "1" > /tmp/output.txt &
jamfHelperPID=$(/bin/echo $!)

# Attempt to detect a new thunderbolt volume, other functions are chained together
detect_new_tbolt_volumes

finish 0
