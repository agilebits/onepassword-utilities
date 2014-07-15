# Importing KeePass 2 Data into 1Password

The script keepass2_to_1p4.pl will convert a KeePass2 XML (2.x) export file into a CSV format that can be imported into 1Password 4.

## Requirements

The script is a Perl script. You will run it in a command shell under either OS X using the Terminal application or under Windows using cmd.exe.

### OS X

- 1Password for Mac, version 4.4 or higher

### Windows

- 1Password for Windows, version 4.0 or higher
- [ActivePerl](http://www.activestate.com/activeperl) version 5.16 or later.

### KeePass 2

- KeePass version 2.x (tested w/2.26, but earlier versions probably work)


## Instructions:

Note: instructions specific to either OS X or Windows will be noted below. They assume you've downloaded the entire onepassword-utilities git repository to your Desktop folder.

### 1. Verify Requirements

Be sure you are running the required version of 1Password as mentioned in the requirements above. If you are using an earlier version, you are advised to update in order to properly import.  Some earlier versions of 1Password had some issues with importing data.

OS X includes Perl. Windows users can download and install ActivePerl for your OS type:

- [32-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x86-298023.msi)
- [64-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x64-298023.msi)

You do not need to install the documentation or example scripts.  Allow the installer to modify your PATH.  When you are done with the conversion, you can uninstall ActivePerl if you want.

### 2. Export KeePass 2 Data

Launch KeePass2, and export its databse to an XML export file using the menu item:

    File > Export ...

and select the KeePass XML (2.x) format.  In the File: Export to: section at the bottom of the dialog, click the floppy disk icon to select the location.  Select your Desktop folder, and in the File name area, enter the name keepass2_export.xml (the remainder of these instructions will assume that name).  Click Save, and you should now have your data exported as an XML file by the name above on your Desktop.  You can quit KeePass2 now if you wish.

### 3. Open Terminal.app or cmd.exe

On OS X, open Terminal (under Applications > Utilities, or type Terminal.app in Spotlight and select it under Applications).  When a Terminal window opens, type:

    cd Desktop/onepassword-utilities/keepass2_to_1p4

and hit Enter.

On Windows, start the command shell by going to the Start menu, and entering cmd.exe in the Search programs and files box, and hit Enter.  When the cmd.exe command line window opens, type:

    cd Desktop\onepassword-utilities\keepass2_to_1p4

and hit Enter.

### 4. Execute the Perl Script

On OS X, in the Terminal window, enter the command:

    perl keepass2_to_1p4.pl -v ../keepass2_export.xml

On Windows, in the command shell, enter the command:

    perl keepass2_to_1p4.pl -v ..\keepass2_export.xml

where keepass2_export.xml is the name you gave to your exported KeePass2 XML file.  The command line above assumes the script is in the folder onepassword-utilities/keepass2_to_1p4 on your Desktop and the exported KeePass2 XML text file is also on your Desktop.  Hit Enter after you've entered the command above.

The script only reads the file you exported from KeePass2, and does not touch your original KeePass2 data file, nor does it send any data anywhere.  Since the script is readable by anyone, you are free and welcome to examine the script and ask questions should you have any concerns.

### 5. Import CSV into 1Password

If all went well, you should now have up to one or more new .csv files on your Desktop, each with a name starting with "1P4_import_", and are conversions of one particular type that can be imported into 1Password 4.  You may not have files for all of the types supported by 1Password 4.  To Import one of the converted files, go to 1Password 4 and use the menu item:

    File > Import

and at the bottom of the dialog, set the File Format to Comma Delimited Text (.csv).  Notice now the Import As pulldown has appeared.  You’ll have to do one import for each type that 1Password 4 currently allows: Login, Credit Cards, Software License, and Secure Notes.  Select one type and match it to the corresponding, newly-created import file (the names should be pretty obvious).  Although the file is greyed out, it will still be selected.

1Password 4 will indicate how many records were imported, and if the import is successful, all your KeePass2 records for the specific type will be imported.  These may require some clean-up, as some fields do not (currently) map into 1Password 4 directly, or may be problematic (certain date fields, for example, or KeePass2's Groups).  However, all unmapped fields will be pushed to the card's Notes field, so the data will be available for you inside 1Password 4.  Your KeePass2 Groups will be listed under Notes with the label Group: and the group hierarchy is shown as a colon-separated list.

### 6. Securely Remove Exported Data

Once you are done importing, be sure to delete the exported keepass2_export.xml file you created in Step 2, as well as the import file created in Step 4 by the converter script, since they contain your unencrypted data.

If you have problems, feel free to post [in this forum thread](https://discussions.agilebits.com/discussion/24909) for assistance.

## Miscellaneous Notes:

### Command line options

Command line options and usage help is available.  For usage help, enter the command:

    perl keepass2_to_1p4.pl --help

### Source Folders

The folder "Text" inside contains the Text::CSV conversion module used by the script.  It is available from CPAN, but is not installed by default on OS X, so is included here for convenience.

### Alternate Download Locations

This script is available at from the 1Password Discussions forum, as well as other download locations. We recommend only downloading from this GitHub repository.

## Special Thanks

A special thank you to @MrC in our [Discussion Forums](https://discussions.agilebits.com) for contributing this script.