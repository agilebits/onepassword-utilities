The script lastpass_to_1p4.pl will convert an LastPass CSV text file export into a 1PIF format
that can be imported into 1Password 4.

Requirements:

    - OS X:
	- 1Password for OS X: version 4.2.2 (422001), or Beta version 4.3.1 or greater.  NOTE:
	  Version 4.3 will not work.

    - Windows:
	- 1Password for Windows: version 4.0.0.BETA-482 or higher.

	- ActivePerl v5.16

    - LastPass:

The script is a Perl script.  You will run it in a command shell under either OS X using the
Terminal application or under Windows using cmd.exe.

Instructions:

Note: instructions specific to either OS X or Windows will be noted below.

1. Be sure you are running the required version of 1Password as mentioned in the requirements above.
If you are using an earlier version, you are advised to update in order to properly import.  Versions
of 1Password earlier than those mentioned above have had some issues with importing data.

For Windows: Download and install ActivePerl for your OS type:

   32-bit: http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x86-298023.msi
   64-bit: http://downloads.activestate.com/ActivePerl/releases/5.16.3.1604/ActivePerl-5.16.3.1604-MSWin32-x64-298023.msi

   You do not need to install the documentation or example scripts.  Allow the installer to
   modify your PATH.  When you are done with the conversion, you can uninstall ActivePerl if
   you want.

2. Open the LastPass web page, and export its database to a CSV text file using the LastPass browser
extension's menu item:

   Tools > Advanced Tools > Export To > LastPass CSV File

and save the file to your Desktop, perhaps as the name lastpass_export.txt (the remainder
of these instructions will assume that name).  Once exported, you can close the browser page if
you wish.

3. (OS X): Launch Terminal.app (under Applications > Utilities, or type terminal.app in Spotlight
and select it under Applications).  When a Terminal window opens, type:

    cd Desktop/lastpass_to_1p4

and hit Enter.

3. (Windows): Start command shell by going to the Start menu, and entering cmd.exe in the Search
programs and files box, and hit Enter.  When the cmd.exe command line window opens, type:

    cd Desktop\lastpass_to_1p4

and hit Enter.

4. (OS X): In the Terminal window, enter the command:

    perl lastpass_to_1p4.pl -v ../lastpass_export.txt

4. (Windows): In the command shell, enter the command:

    perl lastpass_to_1p4.pl -v ..\lastpass_export.txt

where lastpass_export.txt is the name you gave to your exported LastPass CSV file.  The command line
above assumes the script is in the folder lastpass_to_1p4 on your Desktop and the exported LastPass
CSV file is also on your Desktop.  Hit Enter after you've entered the command above.

The script only reads the file you exported from LastPass, and does not touch your original LastPass
data file, nor does it send any data anywhere.  Since the script is readable by anyone, you are
free and welcome to examine the script and ask questions should you have any concerns.

5. If all went well, you should now have the file 1P4_import.1pif on your Desktop.  To Import this
file, go to 1Password 4 and use the menu item:

   File > Import

and select the file 1P4_import.1pif.

1Password 4 will indicate how many records were imported, and if the import is successful, all your
LastPass records for the specific type will be imported.  These may require some clean-up, as some
fields do not (currently) map into 1Password 4 directly, or may be problematic (certain date fields,
for example).  However, any unmapped fields will be pushed to the card's Notes field, so the data
will be available for you inside 1Password 4.

6. Once you are done importing, be sure to delete the exported lastpass_export.txt file you created
in Step 2, as well as the 1P4_import.1pif import file created in Step 4 by the converter script,
since these files contain your unencrypted data.

If you have problems, feel free to post here:

    https://discussions.agilebits.com/discussion/26346

and I’ll help you work through the issues without revealing your private data.

Miscellaneous Notes:

a. Command line options and usage help is available.  For usage help, enter the command:

   perl lastpass_to_1p4.pl --help

b. The included folders "Text" and "UUID" contain the Text::CSV and UUID::Tiny modules used by the
script.  These are included so that you do not have to install them (they are not installed by
default on OS X, so is included here for convenience).  The modules are available on CPAN.

c. This script is available at: https://www.dropbox.com/s/vyex3kt5bta2e6u/lastpass_to_1p4.zip

d. This converter by default sets the Created date for each imported item to 1/1/2000.  This allows
1Password's WatchTower service the ability to flag potentially vulnerabile sites (i.e. for the
HeartBleed security issue).  Unfortunately, there is no way for the converter, and hence 1Password
to know if you have alreadh changed your password on a given site.  This converter errors on the
side of allowing 1Password's WatchTower server the ability to at least warn you of a site's
previous vulnerability so that you can act accordingly.  If you have already changed all of the
potentially vulnerable passwords for your logins, you can include the --nowatchtower option on
the command line to cause the converter to not set the records Created time, and no WatchTower
vulnerabilities will be shown after import.

-MrC
