The script keepassx_to_csv.pl will convert a KeePassX 4.x text file export into a CSV format that
can be imported into 1Password 4.

Requirements:

    - 1Password for Mac: version 4.2.2 (422001), or version 4.3.1 or greater.
      NOTE: Version 4.3 will not work!

    - KeePassX: version 4.x (tested w/4.3, but earlier versions probably work)

The script is a Perl script.  You will run it in Mac OS’ Terminal application. 

Instructions:

1. Be sure your version of 1Password meets the version requirements mentioned above.
If you are using an unsupported version, you will need to update in order to import
the CSV data.  See this post for more information:

    http://discussions.agilebits.com/discussion/comment/119950/#Comment_119950

2. Launch KeePassX, and export its databse to a text file using the menu item:

   File > Export to >  KeePassX XML File...

and save the file to your Desktop, perhaps as the name keepassx_export.xml (the remainder
of these instructions will assume that name).  You can Quit KeePassX if you wish.

3. Launch Terminal.app (under Applications > Utilities, or type terminal.app in Spotlight
and select it under Applications).  When a Terminal window opens, type:

  cd Desktop/keepassx_to_1p4

and hit Enter.

4. Now in Terminal, enter the command:

  perl keepassx_to_1p4.pl ~/Desktop/keepassx_export.xml

where keepassx_export.xml is the name you gave to your exported KeePassX XML file.  The command
line above assumes the script is in the folder keepassx_to_1p4 on your Desktop and the exported
KeePassX XML text file is also on your Desktop.  Hit Enter after you've entered the command above.

The script only reads the file you exported from KeePassX, and does not touch your original
KeePassX data file, nor does it send any data anywhere.  Since the script is readable by anyone,
you are free and welcome to examine the script and ask questions should you have any concerns.

5. If all went well, you should now have a new file on your Desktop called 1P4_import.csv. To import
the converted file, go to 1Password 4 and use the menu item:

   File > Import

and at the bottom of the dialog, set the File Format to Comma Delimited Text (.csv).  Notice now the
Import As pulldown has appeared - select type Login.  Select the file on your Desktop named
1P4_import.csv.  You can ignore the fact tht it is greyed out - it will still be selected.

1Password 4 will indicate how many records were imported, and if the import is successful, all your
KeePassX records will be imported as type Logins.  These may require some clean-up, as some
fields do not (currently) map into 1Password 4 directly, or may be problematic (certain date fields,
for example, or KeePassX's Groups).  However, all unmapped fields will be pushed to the card's Notes
field, so the data will be available for you inside 1Password 4.  Your KeePassX Groups will be listed
under Notes with the label Group: and the group hierarchy is shown as a colon-separated list.

7. Once you are done importing, be sure to delete the exported keepassx_export.xml file you created
in Step 2, as well as the import file created in Step 4 by the converter script, since they contain
your unencrypted data.

If you have problems, feel free to post here:

    http://discussions.agilebits.com/discussion/24381/keepassx-converter-for-1password-4

and I’ll help you work through the issues without revealing your private data.

Miscellaneous Notes:

a. Command line options and usage help is available.  For usage help, in Terminal.app, type:

   perl keepassx_to_1p4.pl --help

b. The folder "Text" inside contains the Text::CSV conversion module used by the script.  It is
available from CPAN, but is not installed by default on OS X, so is included here for convenience.

c. This script is available at: https://dl.dropboxusercontent.com/u/87189402/keepassx_to_1p4.zip

-MrC
