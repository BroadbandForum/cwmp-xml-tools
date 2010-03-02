/*
 * File: FileIntake.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.filehandling;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.util.ArrayList;

/**
 * FileIntake handles files for other parts of the Threepio project.
 * It also is used to resolve files for BBF documents, as their import statements
 * don't always match the files availalbe (missing a level of revision from the filename)
 * @author jhoule
 */
public class FileIntake
{

    /**
     * the file separator that should be used program-wide.
     */
    public static final String fileSep = File.separator;

    /**
     * Returns the part of a file starting with the startSnippet, as a string.
     * @param f - the file
     * @param startSnippet - the string to start copying into the String at.
     * @param model - iff special "model" specific measures should be taken or not.
     * @return the String rep of the portion of the file, empty string if not found.
     * @throws Exception - when unable input the file.
     */
    public static String fileToTrimmedString(File f, String startSnippet, boolean model) throws Exception
    {
        StringBuffer xBuff = fileToStringBuffer(f);

        int where = xBuff.indexOf(startSnippet);

        if (where >= 0)
        {
            xBuff.delete(0, where);

            return xBuff.toString().trim();
        }

        return "";
    }

    /**
     * For BBF documents only!
     * returns true if a file can be resolved for the file given.
     * this is done using resolveFile.
     * @param f - the file to attempt to resolve.
     * @see #resolveFile(java.io.File) 
     * @return true if a a File representing the file that can be resolved, false if none can be.
     * @throws Exception - when an error occurs during the file resolve check.
     */
    public static boolean canResolveFile(File f) throws Exception
    {
        return resolveFile(f, false) != null;
    }


    /**
     * for BBF documents only!
     * returns a file that is resolved for the file given.
     * example: if the file provided is tr-098-1-0.xml, and a file with
     * that filename is not available, the method will try to find
     * a replacement, such as tr-098-1-0-0.xml, and return a File of it.
     * @param original - the file to look for.
     * @param model - if true, makes sure the file is of the highest "model" revision of the candidates.
     * @return a File representing the file that can be resolved, null if none can be.
     * @throws Exception - when the file cannot be found.
     */
    @SuppressWarnings("empty-statement")
    public static File resolveFile(File original, boolean model) throws Exception
    {
        String name;
        File[] files;
        ArrayList<File> matches;
        int comp, revis, other;
        File file, dir;

        if (original == null)
        {
            throw new Exception("File Resolver encountered null File object.");
        }

        name = original.getName();

        if (original.exists())
        {
            if (original.getParentFile() != null)
            {
                // File object represents file and full path to file.
                return original;
            }

            // file doesn't represent full path. this means file is in
            // is the local directory (".").
            // constructing File object for this file, with full path.
            return new File(currentDir().getPath() + File.separatorChar + name);
        }

        // if we get here:
        // the original file doesn't exist, so try to find a file
        // with a very similar path.

        // get the directory the file should be in
        dir = original.getParentFile();

        if (dir == null)
        {
            // relative path has been used. use the directory the code is
            // executing from.
            dir = currentDir();
        }

        if (!dir.exists())
        {
            throw new Exception("directory doesn't exist: " + dir.getAbsolutePath());
        }

        name = removeExt(name);

        files = dir.listFiles();

        // find the file with the name that is most similar.
        comp = Integer.MAX_VALUE;
        matches = new ArrayList<File>();
        for (int i = 0; i < files.length; i++)
        {
            if ((files[i].getName().contains(name)))
            {
                matches.add(files[i]);
            }
        }

        if (model && !matches.isEmpty())
        {
            file = matches.get(0);
            revis = getRevis(name, removeExt(matches.get(0).getName()));
            for (int j = 1; j < matches.size(); j++)
            {
                other = getRevis(name, removeExt(matches.get(0).getName()));

                if (other > revis)
                {
                    file = matches.get(j);
                    revis = other;
                }
            }

            return file;
        }

        for (int j = 0; j < matches.size(); j++)
        {
            if ((Math.abs(matches.get(j).getName().compareToIgnoreCase(name))) < comp)
            {
                return matches.get(j);
            }
        }

        return null;
    }

    /**
     * Finds a file or the closest match to it, based on the path of the File object passed.
     * returns the "best" file, as a File object.
     * @param original - the original file. may or may not exist.
     * @return the best match for the file, null if none found.
     * @throws Exception - file I/O reasons.
     */
    public static File resolveFile(File original) throws Exception
    {
        return resolveFile(original, false);
    }

    /**
     * reads in a file and returns a string rep of it.
     * @param f - the file to read in.
     * @param model - if the file used should be of highest "model" revision.
     * @return the string rep.
     * @throws Exception - when the file cannot be resolved.
     * @see #resolveFile(java.io.File, boolean) 
     */
    public static String fileToString(File f, boolean model) throws Exception
    {
        return fileToStringBuffer(f, model).toString();
    }

    /**
     * reads in a file and returns a string rep of it.
     * @param f - the file
     * @return the string of the file content.
     * @throws Exception - when the file can't be resolved.
     */
    public static String fileToString(File f) throws Exception
    {
        return fileToString(f, false);
    }

    /**
     * reads in a file and returns a string buffer representation of it.
     * @param f - the file to read in.
     * @param model - true if the file should be of the latest "model revision"
     * @return the StringBuffer.
     * @throws Exception - when an error occurs as the file is loaded.
     */
    public static StringBuffer fileToStringBuffer(File f, boolean model) throws Exception
    {
        StringBuffer buff = new StringBuffer();
        BufferedReader reader = null;
        long len;

        f = resolveFile(f);

        if (f == null)
        {
            throw new FileNotFoundException("cannot load into buffer: file not found");
        }

        // read file into buffer
        try
        {
            reader = new BufferedReader(new FileReader(f));
        } catch (Exception ex)
        {
            System.err.println("ERROR: could not open file: " + f.getPath() + " for input.");
            throw (ex);
        }

        try
        {
            len = f.length();

            for (int i = 0; i < len; i++)
            {
                // need to use chars to keep newlines.
                buff.append((char) reader.read());
            }

        } catch (Exception ex)
        {
            System.err.println("Error on file input to buffer: " + ex.getMessage());
            throw (ex);
        }

        reader.close();

        return buff;
    }

    /**
     * reads in a file and returns a string buffer representation of it.
     * @param f - the file to read in.
     * @return the StringBuffer.
     * @throws Exception - when an error occurs as the file is loaded.
     */
    public static StringBuffer fileToStringBuffer(File f) throws Exception
    {
        return fileToStringBuffer(f, false);
    }

    /**
     * gets the directory that the program is executed from, returning it as a File.
     * This is required when the user creates Files with relative paths "it.xml"
     * instead of "c:\what\it.xml."
     * Java does not create getParentDirectory etc for relative Files.
     * @return the directory where the program is executing from, as a File.
     */
    public static File currentDir()
    {
        File dir = new File(".");
        String path = dir.getAbsolutePath();
        path = path.substring(0, path.lastIndexOf(File.separatorChar));
        return new File(path);
    }

    /**
     * returns an integer representation of the "model revision" for a file name.
     * @param stated - the file name stated in a document
     * @param fName - the name of the actual file.
     * @return the revision, as an integer.
     */
    private static int getRevis(String stated, String fName)
    {
        String str = fName.replace(stated, "");

        if (str.isEmpty())
        {
            return 0;
        }

        str = str.replace("-", "");

        return Integer.parseInt(str);
    }

    /**
     * removes the extension from a filename.
     * @param str - the filename.
     * @return the filename, without an extension.
     */
    private static String removeExt(String str)
    {
        // change the name we look for to the file without the extension.
        int delim = str.lastIndexOf('.');

        if (delim >= 0)
        {
            // had an extension. remove it.
            return str.substring(0, delim);
        }

        return str;
    }
}
