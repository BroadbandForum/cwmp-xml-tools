/*
 * File: FileIntake.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.filehandling;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;

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
    public static final String fileSep = System.getProperty("file.separator");
    
    /**
     * Returns the part of a file starting with the startSnippet, as a string.
     * @param f - the file
     * @param startSnippet - the string to start copying into the String at.
     * @return the String rep of the portion of the file, empty string if not found.
     */
    public static String fileToTrimmedString(File f, String startSnippet) throws Exception
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
     */
    public static boolean canResolveFile(File f) throws Exception
    {
        return (resolveFile(f) != null);
    }

    /**
     * for BBF documents only!
     * returns a file that is resolved for the file given.
     * example: if the file provided is tr-098-1-0.xml, and a file with
     * that filename is not available, the method will try to find
     * a replacement, such as tr-098-1-0-0.xml, and return a File of it.
     * @param original - the file to look for.
     * @return a File representing the file that can be resolved, null if none can be.
     */
    @SuppressWarnings("empty-statement")
    public static File resolveFile(File original) throws Exception
    {
        String name, temp;
        File[] files;
        int delim;
        File dir = original.getParentFile();

        if (dir == null)
        {
            dir = currentDir();
        }


        if (!dir.exists())
        {
            throw new Exception("parent directory doesn't exist: " + dir.getAbsolutePath());
        }

        if (!original.exists())
        {

            name = original.getName();
            delim = name.lastIndexOf('.');
            name = name.substring(0, delim);
            files = dir.listFiles();

            int i;
            for (i = 0; i < files.length && !(files[i].getName().contains(name)); i++);

            if (i >= files.length)
            {
                return null;
            }

            return files[i];

        }
        return original;
    }

    /**
     * reads in a file and returns a string represntation of it.
     * @param f - the file to read in.
     * @return the string rep.
     */
    public static String fileToString(File f) throws Exception
    {
        return fileToStringBuffer(f).toString();
    }

    /**
     * reads in a file and returns a string buffer representation of it.
     * @param f - the file to read in.
     * @return the StringBuffer.
     */
    public static StringBuffer fileToStringBuffer(File f) throws Exception
    {
        StringBuffer buff = new StringBuffer();
        BufferedReader reader = null;
        long len;

        f = resolveFile(f);

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

    public static File currentDir()
    {
        File dir = new File(".");
        String path = dir.getAbsolutePath();
        path = path.substring(0, path.lastIndexOf(File.separatorChar));
        return new File(path);
    }
}
