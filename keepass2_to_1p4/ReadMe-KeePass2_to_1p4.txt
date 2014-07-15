The script keepass2_to_1p4.pl will convert a KeePass2 XML (2.x) export file into a CSV
format that can be imported into 1Password 4.

Requirements:

    - 1Password for Mac: version 4.2.2 (422001), or version 4.3.1 or greater.
      NOTE: Version 4.3 will not work!

    - KeePass2: version 2.x (tested w/2.26, but earlier versions probably work)

The script is a Perl script.  You will run it in Mac OS’ Terminal application. 

Instructions:

1. Be sure your version of 1Password meets the version requirements mentioned above.
If you are using an unsupported version, you will need to update in order to import
the CSV data.  See this post for more information:

    http://discussions.agilebits.com/discussion/comment/119950/#Comment_119950

2. Launch KeePass2, and export its databse to an XML export file using the menu item:

   File > Export ...
   
and select the KeePass XML (2.x) format.  In the File: Export to: section at the bottom of the
dialog, click the floppy disk icon to select the location.  Select your Desktop folder, and in
the File name area, enter the name keepass2_export.xml (the remainder of these instructions will
assume that name).  Click Save, and you should now have your data exported as an XML file by the
name above on your Desktop.  You can Quit KeePass2 now if you wish.

3. Launch Terminal.app (under Applications > Utilities, or type terminal.app in Spotlight
and select it under Applications).  When a Terminal window opens, type:

  cd Desktop/keepass2_to_1p4

and hit Enter.

4. Now in Terminal, enter the command:

  perl keepass2_to_1p4.pl -v ~/Desktop/keepass2_export.xml

where keepass2_export.xml is the name you gave to your exported KeePass2 XML file.  The command
line above assumes the script is in the folder keepass2_to_1p4 on your Desktop and the exported
KeePass2 XML text file is also on your Desktop.  Hit Enter after you've entered the command above.

The script only reads the file you exported from KeePass2, and does not touch your original
KeePass2 data file, nor does it send any data anywhere.  Since the script is readable by anyone,
you are free and welcome to examine the script and ask questions should you have any concerns.

5. If all went well, you should now have up to one or more new .csv files on your Desktop, each with
a name starting with "1P4_import_", and are conversions of one particular type that can be imported
into 1Password 4.  You may not have files for all of the types supported by 1Password 4.  To Import
one of the converted files, go to 1Password 4 and use the menu item:

   File > Import

and at the bottom of the dialog, set the File Format to Comma Delimited Text (.csv).  Notice now the
Import As pulldown has appeared.  You’ll have to do one import for each type that 1Password 4 currently
allows: Login, Credit Cards, Software License, and Secure Notes.  Select one type and match it to the
corresponding, newly-created import file (the names should be pretty obvious).  Although the file is
greyed out, it will still be selected.

1Password 4 will indicate how many records were imported, and if the import is successful, all your
KeePass2 all your eWallet records for the specific type will be imported.  These may require some
clean-up, as some fields do not (currently) map into 1Password 4 directly, or may be problematic
(certain date fields, for example, or KeePass2's Groups).  However, all unmapped fields will be pushed
to the card's Notes field, so the data will be available for you inside 1Password 4.  Your KeePass2
Groups will be listed under Notes with the label Group: and the group hierarchy is shown as a colon-
separated list.

7. Once you are done importing, be sure to delete the exported keepass2_export.xml file you created
in Step 2, as well as the import file created in Step 4 by the converter script, since they contain
your unencrypted data.

If you have problems, feel free to post here:

    http://discussions.agilebits.com/discussion/24909/keepass2-converter-for-1password-4

and I’ll help you work through the issues without revealing your private data.

Miscellaneous Notes:

a. Command line options and usage help is available.  For usage help, in Terminal.app, type:

   perl keepass2_to_1p4.pl --help

b. The folder "Text" inside contains the Text::CSV conversion module used by the script.  It is
available from CPAN, but is not installed by default on OS X, so is included here for convenience.

c. This script is available at: https://dl.dropboxusercontent.com/u/87189402/keepass2_to_1p4.zip

-MrC
