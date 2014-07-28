# Importing KeePassX Data into 1Password

The script keepassx_to_csv.pl will convert a KeePassX 4.x text file export into a CSV format that can be imported into 1Password 4.

## Requirements

The script is a Perl script. You will run it in a command shell under either OS X using the Terminal application or under Windows using cmd.exe.

### OS X

- 1Password for Mac, version 4.4 or higher

### Windows

- 1Password for Windows, version 4.0 or higher
- [ActivePerl](http://www.activestate.com/activeperl) version 5.16 or later.

### KeePassX

- KeePassX version 4.x (tested w/4.3, but earlier versions probably work)


## Instructions:

Note: instructions specific to either OS X or Windows will be noted below. They assume you've downloaded the entire onepassword-utilities git repository to your Desktop folder.

### 1. Verify Requirements

Be sure you are running the required version of 1Password as mentioned in the requirements above. If you are using an earlier version, you are advised to update in order to properly import.  Some earlier versions of 1Password had some issues with importing data.

OS X includes Perl. Windows users can download and install ActivePerl for your OS type:

- [32-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x86-298023.msi)
- [64-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x64-298023.msi)

You do not need to install the documentation or example scripts.  Allow the installer to modify your PATH.  When you are done with the conversion, you can uninstall ActivePerl if you want.

### 2. Export KeePassX Data

Launch KeePassX, and export its database to a text file using the menu item:

    File > Export to > KeePassX XML File...

and save the file to your Desktop, perhaps as the name keepassx_export.xml (the remainder of these instructions will assume that name).  You can Quit KeePassX if you wish.

### 3. Open Terminal.app or cmd.exe

On OS X, open Terminal (under Applications > Utilities, or type Terminal.app in Spotlight and select it under Applications).  When a Terminal window opens, type:

    cd Desktop/onepassword-utilities/keepassx_to_1p4

and hit Enter.

On Windows, start the command shell by going to the Start menu, and entering cmd.exe in the Search programs and files box, and hit Enter.  When the cmd.exe command line window opens, type:

    cd Desktop\onepassword-utilities\keepassx_to_1p4

and hit Enter.

### 4. Execute the Perl Script

On OS X, in the Terminal window, enter the command:

    perl keepassx_to_1p4.pl -v ../keepassx_export.xml

On Windows, in the command shell, enter the command:

    perl keepassx_to_1p4.pl -v ..\keepassx_export.xml

where keepassx_export.xml is the name you gave to your exported KeePassX XML file.  The command line above assumes the script is in the folder onepassword-utilities/keepassx_to_1p4 on your Desktop and the exported KeePassX XML text file is also on your Desktop.  Hit Enter after you've entered the command above.

The script only reads the file you exported from KeePassX, and does not touch your original KeePassX data file, nor does it send any data anywhere.  Since the script is readable by anyone, you are free and welcome to examine the script and ask questions should you have any concerns.

### 5. Import CSV into 1Password

If all went well, you should now have a new file on your Desktop called 1P4_import.csv. To import the converted file, go to 1Password 4 and use the menu item:

    File > Import

and at the bottom of the dialog, set the File Format to Comma Delimited Text (.csv).  Notice now the Import As pulldown has appeared - select type Login.  Select the file on your Desktop named 1P4_import.csv.  You can ignore the fact that it is greyed out - it will still be selected.

1Password 4 will indicate how many records were imported, and if the import is successful, all your KeePassX records will be imported as type Logins.  These may require some clean-up, as some fields do not (currently) map into 1Password 4 directly, or may be problematic (certain date fields, for example, or KeePassX's Groups).  However, all unmapped fields will be pushed to the card's Notes field, so the data will be available for you inside 1Password 4.  Your KeePassX Groups will be listed under Notes with the label Group: and the group hierarchy is shown as a colon-separated list.

### 6. Securely Remove Exported Data

Once you are done importing, be sure to delete the exported keepassx_export.xml file you created in Step 2, as well as the import file created in Step 4 by the converter script, since they contain your unencrypted data.

If you have problems, feel free to post [in this forum thread](https://discussions.agilebits.com/discussion/24381) for assistance.

## Miscellaneous Notes:

### Command line options

Command line options and usage help is available.  For usage help, enter the command:

    perl keepassx_to_1p4.pl --help

### Source Folders

The folder "Text" inside contains the Text::CSV conversion module used by the script.  It is available from CPAN, but is not installed by default on OS X, so is included here for convenience.

### Alternate Download Locations

This script is available from the 1Password Discussions forum and other download locations. We recommend downloading only from this GitHub repository.

### Watchtower

The "modified date" of imported items will be recorded as the time and date they were imported. For that reason, 1Password’s Watchtower service will not be able to accurately assess these items' vulnerability. If you have not recently changed the passwords for your imported items, we recommend visiting [our Watchtower page](https://watchtower.agilebits.com/) and entering the URLs, one at a time, to check for vulnerabilities.

## Special Thanks

A special thank you to @MrC in our [Discussion Forums](https://discussions.agilebits.com) for contributing this script.