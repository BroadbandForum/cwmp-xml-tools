/*
 * File: FilePrinter.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.printer;

import java.io.File;
import threepio.tabler.container.XTable;

/**
 * A FilePrinter prints out a queue containing model data to a file, or string.
 *
 * @author jhoule
 */
public abstract class FilePrinter
{

    static String rowTag, tableTag = "TABLE", colTag, newLine = System.getProperty("line.separator");
    static char leftBrack, rightBrack;

    /**
     * converts a table to a String that is the contents of a file
     * made by parsing the document.
     * @param table - the table to convert
     * @param diffMode - sets method to insert diff formatting or not
     * @param looks - sets the method to do cosmetic work or not.
     * @throws Exception - when there is a file missing or an IO error.
     * @return the file, as a string.
     */
    public abstract String convertTable(XTable table, boolean diffMode, boolean looks) throws Exception;

    /**
     * a shortcut for converting a table without diffing.
     * @param table - the table to convert
     * @return the file, as a string.
     * @throws Exception - when there is a file missing or an IO error.
     */
    public String convertTable(XTable table) throws Exception
    {
        return convertTable(table, false, false);
    }

    /**
     * prints a table to a file, returning that file.
     * @param table - the table to print.
     * @param file - the file to print to.
     * @return true if it went okay, false if not.
     */
    public abstract File printTable(XTable table, File file);

    /**
     * carries out any setting up of variables, including all statics
     */
    abstract void setUp();
}
