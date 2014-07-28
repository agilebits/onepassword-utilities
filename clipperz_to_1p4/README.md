# Importing Clipperz Data into 1Password

The script clipperz_to_1p4.pl will convert a Clipperz JSON text export file export into a 1PIF format that can be imported into 1Password 4.  By default, the script will create a .1pif file, as the .1pif format has superior importing capabilities.

## Requirements

The script is a Perl script. You will run it in a command shell under either OS X using the Terminal application or under Windows using cmd.exe.

### OS X

- 1Password for Mac, version 4.4 or higher

### Windows

- 1Password for Windows, version 4.0 or higher
- [ActivePerl](http://www.activestate.com/activeperl) version 5.16 or later.


## Instructions:

Note: instructions specific to either OS X or Windows will be noted below. They assume you've downloaded the entire onepassword-utilities git repository to your Desktop folder.

### 1. Verify Requirements

Be sure you are running the required version of 1Password as mentioned in the requirements above. If you are using an earlier version, you are advised to update in order to properly import.  Some earlier versions of 1Password had some issues with importing data.

OS X includes Perl. Windows users can download and install ActivePerl for your OS type:

- [32-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x86-298023.msi)
- [64-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x64-298023.msi)

You do not need to install the documentation or example scripts.  Allow the installer to modify your PATH.  When you are done with the conversion, you can uninstall ActivePerl if you want.

### 2. Export Clipperz Data

Open Clipperz and export its database to the JSON format using the menu item and save the file to your Desktop, perhaps with the name clipperz_export.txt (the remainder of these instructions will assume that name).  You can then quit Clipperz if you wish.

### 3. Open Terminal.app or cmd.exe

On OS X, open Terminal (under Applications > Utilities, or type Terminal.app in Spotlight and select it under Applications).  When a Terminal window opens, type:

    cd Desktop/onepassword-utilities/clipperz_to_1p4

and hit Enter.

On Windows, start the command shell by going to the Start menu, and entering cmd.exe in the Search programs and files box, and hit Enter.  When the cmd.exe command line window opens, type:

    cd Desktop\onepassword-utilities\clipperz_to_1p4

and hit Enter.

### 4. Execute the Perl Script

On OS X, in the Terminal window, enter the command:

    perl clipperz_to_1p4.pl -v ../clipperz_export.txt

On Windows, in the command shell, enter the command:

    perl clipperz_to_1p4.pl -v ..\clipperz_export.txt

where clipperz_export.txt is the name you gave to your exported Clipperz JSON file.  The command line above assumes the script is in the folder onepassword-utilities/clipperz_to_1p4 on your Desktop and the exported clipperz JSON file is also on your Desktop.  Hit Enter after you've entered the command above.

The script only reads the file you exported from Clipperz, and does not touch your original Clipperz data, nor does it send any data anywhere.  Since the script is readable by anyone, you are free and welcome to examine the script and ask questions should you have any concerns.

### 5. Import 1PIF into 1Password

If all went well, you should now have the file 1P4_import.1pif on your Desktop.  To Import this file, go to 1Password 4 and use the menu item:

    File > Import

and select the file 1P4_import.1pif.

1Password 4 will indicate how many records were imported, and if the import is successful, all your Clipperz records for the specific type will be imported.  These may require some clean-up, as some fields do not (currently) map into 1Password 4 directly, or may be problematic (certain date fields, for example). However, any unmapped fields will be pushed to the card's Notes field, so the data will be available for you inside 1Password 4.

### 6. Securely Remove Exported Data

Once you are done importing, be sure to delete the exported clipperz_export.txt file you created in Step 2, as well as the 1P4_import.1pif import file created in Step 4 by the converter script, since these files contain your unencrypted data.

If you have problems, feel free to post [in this forum thread](https://discussions.agilebits.com/discussion/25589) for assistance.


## Miscellaneous Notes:

### Command line options

Command line options and usage help is available.  For usage help, enter the command:

    perl clipperz_to_1p4.pl --help

### Source Folders
The included folders "Text" and "UUID" contain the Text::CSV and UUID::Tiny modules used by the script.  These are included so that you do not have to install them (they are not installed by default on OS X, so is included here for convenience).  The modules are available on CPAN.

### Alternate Download Locations

This script is available from the 1Password Discussions forum and other download locations. We recommend downloading only from this GitHub repository.

### Watchtower

This converter by default sets the Created date for each imported item to 1/1/2000.  This allows 1Password's Watchtower service the ability to flag potentially vulnerable sites (e.g. for the Heartbleed security issue).  Unfortunately, there is no way for the converter, and hence 1Password, to know if you have already changed your password on a given site.  This converter errs on the side of allowing 1Password's Watchtower server the ability to at least warn you of a site's previous vulnerability so that you can act accordingly.  If you have already changed all of the potentially vulnerable passwords for your logins, you can include the `--nowatchtower` option on the command line to cause the converter to not set the records Created time, and no Watchtower vulnerabilities will be shown after import.

## Special Thanks

A special thank you to @MrC in our [Discussion Forums](https://discussions.agilebits.com) for contributing this script.