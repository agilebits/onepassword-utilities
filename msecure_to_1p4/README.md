# Importing mSecure Data into 1Password

The script msecure_to_1p4.pl will convert an mSecure 3.5.x text file export into a CSV format that can be imported into 1Password 4.

## Requirements

The script is a Perl script. You will run it in a command shell under either OS X using the Terminal application or under Windows using cmd.exe.

### OS X

- 1Password for Mac, version 4.4 or higher

### Windows

- 1Password for Windows, version 4.0 or higher
- [ActivePerl](http://www.activestate.com/activeperl) version 5.16 or later.

### mSecure

- mSecure version 3.5.x (tested w/3.5.3, but earlier versions probably work)


## Instructions:

Note: instructions specific to either OS X or Windows will be noted below. They assume you've downloaded the entire onepassword-utilities git repository to your Desktop folder.

### 1. Verify Requirements

Be sure you are running the required version of 1Password as mentioned in the requirements above. If you are using an earlier version, you are advised to update in order to properly import.  Some earlier versions of 1Password had some issues with importing data.

OS X includes Perl. Windows users can download and install ActivePerl for your OS type:

- [32-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x86-298023.msi)
- [64-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x64-298023.msi)

You do not need to install the documentation or example scripts.  Allow the installer to modify your PATH.  When you are done with the conversion, you can uninstall ActivePerl if you want.

### 2. Export mSecure Data

Launch mSecure, and export its database to a text file using the menu item:

    File > Export > CSV ...

You probably want to leave the Export all records setting selected.  Save the file to your Desktop, perhaps as the name msecure_export.csv (the remainder of these instructions will assume that name).  You can Quit mSecure if you wish.

### 3 Open Terminal.app or cmd.exe

On OS X, open Terminal (under Applications > Utilities, or type terminal.app in Spotlight and select it under Applications).  When a Terminal window opens, type:

    cd Desktop/onepassword-utilities/msecure_to_1p4

and hit Enter.

On Windows, start the command shell by going to the Start menu, and entering cmd.exe in the Search programs and files box, and hit Enter.  When the cmd.exe command line window opens, type:

    cd Desktop\onepassword-utilities\msecure_to_1p4

and hit Enter.

### 4. Execute the Perl Script

On OS X, in the Terminal window, enter the command:

    perl msecure_to_1p4.pl -v ../msecure_export.csv

On Windows, in the command shell, enter the command:

    perl msecure_to_1p4.pl -v ..\msecure_export.csv

The file msecure_export.csv is the name you gave to your exported mSecure CSV file.  The command line above assumes the script is in the folder onepassword-utilities/msecure_to_1p4 on your Desktop and the exported mSecure CSV file is also on your Desktop.  Hit Enter after you've entered the command above.

The script only reads the file you exported from mSecure, and does not touch your original mSecure data file, nor does it send any data anywhere.  Since the script is readable by anyone, you are free and welcome to examine the script and ask questions should you have any concerns.

If you are using a different language, use the following form:

    perl msecure_to_1p4.pl -v --lang XX ../msecure_export.csv

or for Windows

    perl msecure_to_1p4.pl -v --lang XX ..\msecure_export.csv

replacing the XX with your language code from the following supported language codes:

    de es fr it ja ko pl pt ru zh-Hans zh-Hant.


### 5. Import CSV into 1Password

If all went well, you should now have up to 3 new .csv files on your Desktop, each with a name starting with "1P4_import_", and are conversions of one particular type that can be imported into 1Password 4.  To Import one of the converted files, go to 1Password 4 and use the menu item:

    File > Import

and at the bottom of the dialog, set the File Format to Comma Delimited Text (.csv).  Notice now the Import As pulldown has appeared.  You’ll have to do one import for each type that 1Password 4 currently allows: Login, Credit Cards, Software License, and Secure Notes.  Select one type and match it to the corresponding, newly-created import file (the names should be pretty obvious).  You may not have all four files; it depends on the entry types you had in your original mSecure database. 

1Password 4 will indicate how many records were imported, and if the import is successful, all your mSecure records for the specific type will be imported.  These may require some clean-up, as some fields do not (currently) map into 1Password 4 directly, or may be problematic (certain date fields, for example, or mSecure's Groups).  However, all unmapped fields will be pushed to the card's Notes field, so the data will be available for you inside 1Password 4.


### 6. Securely Remove Exported Data

Once you are done importing, be sure to delete the exported msecure_export.csv file you created in Step 2, as well as the (up to) three import files created in Step 4 by the converter script, since they contain your unencrypted data.

If you have problems, feel free to post [in this forum thread](https://discussions.agilebits.com/discussion/26346) for assistance.


## Miscellaneous Notes:

### Command line options

Command line options and usage help is available.  For usage help, in Terminal.app, type:

    perl msecure_to_1p4.pl --help

### Source Folders

The folder "Text" inside contains the Text::CSV conversion module used by the script.  It is available from CPAN, but is not installed by default on OS X, so is included here for convenience.

### Alternate Download Locations

This script is available from the 1Password Discussions forum and other download locations. We recommend downloading only from this GitHub repository.

### Watchtower

The "modified date" of imported items will be recorded as the time and date they were imported. For that reason, 1Password’s Watchtower service will not be able to accurately assess these items' vulnerability. If you have not recently changed the passwords for your imported items, we recommend visiting [our Watchtower page](https://watchtower.agilebits.com/) and entering the URLs, one at a time, to check for vulnerabilities.


## Special Thanks

A special thank you to @MrC in our [Discussion Forums](https://discussions.agilebits.com) for contributing this script.