![Alt text](gallery/SimpleNotes.png?raw=true "Sample screenshot of Simple Notes")  

# Simple Notes
A minimalist note taking Android app with the option to export notes to a text file.  
Since Hive is used to store the notes, it is perhaps stored in the User's app directory (https://docs.hivedb.dev/#/more/limitations), rather than in the cache.  
When notes are exported as a text file, they are stored in `Android/data/com.nav.notes.simple_notes/files/` as `.txt` files with a unique timestamp of the time it was saved at. Having multiple such versions offers a good backup in case of file corruption. You will of course have to manually delete the files periodically.  

# Attributions
* The code was generated by prompting ChatGPT.
* The app icon is from [Document icons created by Haris Masood - Flaticon](https://www.flaticon.com/free-icons/document).

# TODO
* An option for the User to specify the folder to save files to.  
* An option or menu on the home-screen to delete all old `.txt` files.
