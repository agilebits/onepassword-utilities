The script msecure_to_1p4.pl will convert an mSecure 3.5.x text file export into a CSV
format that can be imported into 1Password 4.

Requirements:

    - 1Password for Mac: version 4.2.2 (422001), or version 4.3.1 or greater.
      NOTE: Version 4.3 will not work!

    - mSecure: version 3.5.x (tested w/3.5.3, but earlier versions probably work)

The script is a Perl script.  You will run it in Mac OS’ Terminal application. 

Instructions:

1. Be sure you are running version 1Password 4.3.1 or later.   If you are using an earlier
version, you will need to update in order to import the CSV data.  See this post for more
information:

    http://discussions.agilebits.com/discussion/comment/119950/#Comment_119950

2. Launch mSecure, and export its databse to a text file using the menu item:

   File > Export > CSV ...

You probably want to leave the Export all records setting selected.  Save the file to your
Desktop, perhaps as the name msecure_export.csv (the remainder of these instructions will
assume that name).  You can Quit mSecure if you wish.

3. Launch Terminal.app (under Applications > Utilities, or type terminal.app in Spotlight
and select it under Applications).  When a Terminal window opens, type:

  cd Desktop/msecure_to_1p4

and hit Enter.

4. Now in Terminal, enter one of the two commands below depending upon your language. If you are
using an English language wallet, use:

  perl msecure_to_1p4.pl ~/Desktop/msecure_export.csv

Otherwise use the following form:

  perl msecure_to_1p4.pl --lang XX ~/Desktop/msecure_export.csv

replacing the XX with your language code from the following supported language codes:

   de es fr it ja ko pl pt ru zh-Hans zh-Hant.

The file msecure_export.csv is the name you gave to your exported mSecure CSV file.  The command line
above assumes the script is in the folder msecure_to_1p4 on your Desktop and the exported mSecure
CSV file is also on your Desktop.  Hit Enter after you've entered the command above.

The script only reads the file you exported from mSecure, and does not touch your original mSecure
data file, nor does it send any data anywhere.  Since the script is readable by anyone, you are
free and welcome to examine the script and ask questions should you have any concerns.

5. If all went well, you should now have up to 3 new .csv files on your Desktop, each with a name
starting with "1P4_import_", and are conversions of one particular type that can be imported into
1Password 4.  To Import one of the converted files, go to 1Password 4 and use the menu item:

   File > Import

and at the bottom of the dialog, set the File Format to Comma Delimited Text (.csv).  Notice now the
Import As pulldown has appeared.  You’ll have to do one import for each type that 1Password 4 currently
allows: Login, Credit Cards, Software License, and Secure Notes.  Select one type and match it to the
corresponding, newly-created import file (the names should be pretty obvious).  You may not have all
four files; it depends on the entry types you had in your original mSecure database.

1Password 4 will indicate how many records were imported, and if the import is successful, all your
mSecure records for the specific type will be imported.  These may require some clean-up, as some
fields do not (currently) map into 1Password 4 directly, or may be problematic (certain date fields,
for example, or mSecure's Groups).  However, all unmapped fields will be pushed to the card's Notes
field, so the data will be available for you inside 1Password 4.

7. Once you are done importing, be sure to delete the exported msecure_export.csv file you created
in Step 2, as well as the (up to) three import files created in Step 4 by the converter script,
since they contain your unencrypted data.

If you have problems, feel free to post here:

    http://discussions.agilebits.com/discussion/24754/msecure-converter-for-1password-4

and I’ll help you work through the issues without revealing your private data.

Miscellaneous Notes:

a. Command line options and usage help is available.  For usage help, in Terminal.app, type:

   perl msecure_to_1p4.pl --help

b. The folder "Text" inside contains the Text::CSV conversion module used by the script.  It is
available from CPAN, but is not installed by default on OS X, so is included here for convenience.

c. This script is available at: https://dl.dropboxusercontent.com/u/87189402/msecure_to_1p4.zip

-MrC
