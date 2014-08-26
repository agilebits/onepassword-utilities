# Importing KeePass 2 Data into 1Password

The script keepass2_to_1p4.pl will convert a KeePass 2 XML (2.x) export file into a 1PIF
format that can be imported into 1Password.

## Requirements

The script is a Perl script.  You will run it in a command shell under OS X using the
**Terminal** application or under Windows using the **cmd.exe** command shell.

### OS X
- 1Password for Mac, version 4.4 or higher

### Windows

- 1Password for Windows, version 4.0 or higher
- [ActivePerl](http://www.activestate.com/activeperl) version 5.16 (not 5.18)

### KeePass 2

- KeePass version 2.x (tested with version 2.26, but earlier versions probably work)


## Instructions

Instructions specific to either OS X or Windows will be noted below. The instructions assume you have
downloaded the entire [onepassword-utilities](https://github.com/AgileBits/onepassword-utilities) git repository to your Desktop folder.


### 1. Verify Requirements

Be sure you are running the required version of 1Password as mentioned in the requirements above. If
you are using an earlier version, you will need to update in order to properly import.  Earlier
versions of 1Password had some issues with importing data.

OS X includes Perl, so no additional software is required. Windows users will need to download and
install ActivePerl for your OS type:

- [32-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x86-298023.msi)
- [64-bit](http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x64-298023.msi)

You do not need to install the documentation or example scripts.  Allow the installer to modify your
PATH (otherwise you will need to specify the full path to the perl program below).  When you are
done with the conversion, you may uninstall ActivePerl.

### 2. Export KeePass 2 Data

Launch KeePass 2, and export its database to an XML export file using the menu item:

    File > Export ...

and select the KeePass XML (2.x) format.  In the `File: Export to:` section at the bottom of the
dialog, click the floppy disk icon to select the location.  Select your **Desktop** folder, and in
the File name area, enter the name **keepass2_export.xml** (the remainder of these instructions will
assume that name).  Click **Save**, and you should now have your data exported as an XML file by the
name above on your Desktop.  You may now Quit KeePass 2 now.

### 3. Open the Command Line Shell

On OS X, open **Terminal** (under Applications > Utilities, or type **Terminal.app** in Spotlight and select
it under Applications).  When a Terminal window opens, type (or copy and paste):

    cd Desktop/onepassword-utilities/keepass2_to_1p4

and hit Enter.

On Windows, start the command shell by going to the Start menu, and entering **cmd.exe** in the *Search
programs and files box*, and hit Enter.  When the cmd.exe command line window opens, type:

    cd Desktop\onepassword-utilities\keepass2_to_1p4

and hit Enter.

### 4. Execute the Perl Script

On OS X, in the Terminal window, enter the command:

    perl keepass2_to_1p4.pl -v ../../keepass2_export.xml

On Windows, in the command shell, enter the command:

    perl keepass2_to_1p4.pl -v ..\..\keepass2_export.xml

where keepass2_export.xml is the name you gave to your exported KeePass 2 XML file.  The command
line above assumes the script is in the folder onepassword-utilities/keepass2_to_1p4 (OS X) or
onepassword-utilities\keepass2_to_1p4 (Windows) on your Desktop and the exported KeePass 2 XML text
file is also on your Desktop.  Hit Enter after you've entered the command above.

The script only reads the file you exported from KeePass 2, and does not touch your original
KeePass 2 data file, nor does it send any data anywhere.  Since the script is readable by anyone,
you are free and welcome to examine the script and ask questions should you have any concerns.

### 5. Import 1PIF into 1Password

If the conversion was successful, there will be a file named **1P4_import.1pif** on your Desktop.  To
Import this file, use the 1Password  `File > Import` menu and select the file 1P4_import.1pif.

1Password will indicate how many records were imported, and if the import is successful, all of your
KeePass 2 records should now be available in 1Password.  These records may require some clean-up, as
some fields do not (currently) map into 1Password 4 directly, or may be problematic (certain date
fields, for example). Any unmapped fields will be pushed to an item's Notes field, so the
data will be available for you within the 1Password entry.  Your KeePass 2 Groups will be created as a
colon-separated list of 1Password 4 Tags (note: these are not currently shown in the UI of the
Windows version of 1Password, however, the Tags do exist within the database file).

### 6. Securely Remove Exported Data

Once you are done importing, be sure to securely delete the exported keepass2_export.xml file you
created in Step 2, as well as the import file created by the converter script in Step 4, since these
contain your unencrypted data.

If you have problems, feel free to post [in this forum thread](https://discussions.agilebits.com/discussion/24909) for assistance.

## Miscellaneous Notes

### Command line options

Usage help and several command line options are available.  For usage help in the commmand shell window,
enter the command:

    perl keepass2_to_1p4.pl --help

The `--sparselogin` and `--watchtower` options are described below.

### Sparselogin
The default mode of operation is that the script will create a Login item only if both the username
and password are present and non-empty; otherwise, a Secure Note is created.  The `--sparselogin`
option will defeat this default, and will create a Login item when at least one of the username or
password or password exists in an entry.  

### Watchtower

This converter sets the Created date for each imported item to 1/1/2000.  This allows 1Password's
Watchtower service the ability to flag potentially vulnerabile sites (i.e. for the HeartBleed
security issue).  Unfortunately, there is no way for the converter, and hence 1Password, to know if
you have already changed your password for a given site.  This converter errors on the side of
allowing 1Password's Watchtower service the ability to at least warn you of a site's previous
vulnerability so that you can act accordingly.  If you have already changed all of the potentially
vulnerable passwords for your logins, you can include the `--nowatchtower` option on the command
line to cause the converter to not set the record's Created time, and no Watchtower vulnerabilities
will be shown upon import.

If you have not recently changed the passwords for your imported items, AgileBits recommends
visiting [the Watchtower page](https://watchtower.agilebits.com/) and entering the URLs, one at a time, to check for vulnerabilities.

### Source Folders

The included folders **JSON** and **UUID** contain code modules used by the conversion script. 
These are included for your convenience in case they are not installed on your system.  These
modules are commonly used or bundled Perl modules, and are available on CPAN.

### Alternate Download Locations

This script and updates are available from the 1Password Discussions forum and other download
locations. AgileBits recommends downloading only from the GitHub repository referenced in AgileBit's
guide [Import your data](https://guides.agilebits.com/knowledgebase/1password4/en/topic/import).

-MrC
