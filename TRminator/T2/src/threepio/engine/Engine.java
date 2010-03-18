/*
 * File: Engine.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.engine;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.logging.Level;
import java.util.logging.Logger;
import threepio.container.Doublet;
import threepio.documenter.XDocumenter;
import threepio.filehandling.FileIntake;
import threepio.printer.FilePrinter;
import threepio.tabler.ModelTableDiffer;
import threepio.tabler.ModelTabler;
import threepio.tabler.container.ColumnMap;
import threepio.tabler.container.ModelTable;
import threepio.tabler.container.Row;
import threepio.tabler.container.XTable;

/**
 * Engine is an app that works with model tables, making them using Tablers.
 * @author jhoule
 */
public abstract class Engine
{

    /**
     * docToPrintedModelTable turns an XDoc object into a ModelTable object, and prints it out
     * as an HTML table, to a file.
     * @param cols - an IHM of the columns to use for the table.
     * @param ID - the ID of the body in the file to put into the ModelTable.
     * @param pathIn - the path for the file to examine.
     * @param fileOut - the file to place the ModelTable into.
     * @param majorItemType - the type of item that defines a row
     * @param diff - denotes whether or not to diff the model against the model before it.
     * @param profiles - denotes whether or not to append a table of Model items from doc(s)
     * @param looks - denotes whether or not to add newlines (HTML) to make the info fit in a table.
     * @return true if the table was produced correctly, false if there was a problem.
     * @throws Exception - in the case of any error returned by subroutines.
     */
    public boolean docToPrintedModelTable(ColumnMap cols, String ID, String pathIn, File fileOut, String majorItemType, boolean diff, boolean profiles, boolean looks) throws Exception
    {
        return printModelTable(docToModelTable(cols, ID, pathIn, majorItemType), fileOut, diff, profiles, looks);
    }

    /**
     * prints a Model Table to a file.
     * @param table - the table to print out.
     * @param fileOut - the file to print to.
     * @param diff - if the table should include "diff" formatting based on previous version(s) or not.
     * @param profiles - if a table of "profile" objects should be included or not.
     * @param looks - if special measures should be taken to make the output look better.
     * @return true iff the table was printed correctly, false iff not.
     * @throws Exception - in teh case of any error returned by subroutines.
     */
    public abstract boolean printModelTable(ModelTable table, File fileOut, boolean diff, boolean profiles, boolean looks) throws Exception;


    /**
     *
     * @param cols - an IHM of the columns to use for the table.
     * @param ID - the ID of the body in the file to put into the ModelTable.
     * @param pathIn - the path for the file to examine.
     * @param majorItemType - the type of item that defines a row
     * @return the table based on the input.
     * @throws Exception - in the case of any error returned by subroutines.
     */
    public ModelTable docToModelTable(ColumnMap cols, String ID, String pathIn, String majorItemType) throws Exception
    {
        ModelTable table = null;
        TablerController controller = new TablerController(cols);

        try
        {
            table = controller.makeWholeTable(ID, pathIn, majorItemType, true);

        } catch (Exception ex)
        {

            Logger.getLogger(ThreepioEngine.class.getName()).log(Level.SEVERE, "problem making table", ex);
            throw (ex);
        }

        return table;
    }

    /**
     * shortcut for print table, where diffing is not involved.
     * @param table - the table to print out.
     * @param printer - the printer to use
     * @param fileOut - the file to print the ModelTable out to.
     * @return true if the print worked, false if not.
     * @throws Exception - when printing errors occur
     */
    protected boolean printTable(XTable table, FilePrinter printer, File fileOut) throws Exception
    {
        return printTable(table, printer, fileOut, "", "", false, false);
    }

    /**
     * prints a Model Table to a file.
     * @param table - the table to print out.
     * @param fileOut - the file to print to.
     * @param looks - if special measures should be taken to make the output look better.
     * @return true iff the table was printed correctly, false iff not.
     * @throws Exception - in teh case of any error returned by subroutines.
     */
    public boolean printModelTable(ModelTable table, File fileOut, boolean looks) throws Exception
    {
        return printModelTable(table, fileOut, false, false, looks);
    }

    /**
     * prints a Model Table to a file.
     * @param table - the table to print out.
     * @param fileOut - the file to print to.
     * @return true iff the table was printed correctly, false iff not.
     * @throws Exception - in teh case of any error returned by subroutines.
     */
    public boolean printModelTable(ModelTable table, File fileOut) throws Exception
    {
        return printModelTable(table, fileOut, false, false, false);
    }

    /**
     * (experimental) xmlToPrintedModelTable makes any XML file with a sound heiarchy
     * into an HTML table.
     * @param ID - name of object to table
     * @param printer - the file printer to use.
     * @param pathIn - the path for the file to use as input.
     * @param fileOut - the file to output the table to.
     * @param cols - IHM of columns to use.
     * @return true if the conversion worked, false if not.
     * @throws Exception - upon most any error.
     */
    public boolean xmlToPrintedModelTable(ColumnMap cols, FilePrinter printer, String ID, String pathIn, File fileOut) throws Exception
    {
        return printTable((ModelTable) xmlToModelTable(cols, ID, pathIn), printer, fileOut);
    }

    /**
     * xmlToModelTable converts a chunk of XML data to a  ModelTable
     * @param cols - an IHM of the columns the table should have.
     * @param ID - the version or ID for the Table.
     * @param pathIn - the path of the input file.
     * @return - the XML information as a simple Table.
     * @throws Exception - when there is a problem converting.
     * @see XTable
     */
    private XTable xmlToModelTable(ColumnMap cols, String ID, String pathIn) throws Exception
    {
        ModelTabler mTabler = new ModelTabler(cols);
        XDocumenter documenter = new XDocumenter();

        XTable table = null;

        // don't use for models anyway, do we?
        File file = FileIntake.resolveFile(new File(pathIn));

        try
        {
            table = (ModelTable) mTabler.parseContainer(documenter.convertFile(file), "name", ID, true);
            table.put(0, mTabler.getHeader());
        } catch (Exception ex)
        {
            Logger.getLogger(ThreepioEngine.class.getName()).log(Level.SEVERE, "could not document and table the file.", ex);
            throw (ex);
        }

        return table;
    }

    /**
     * diffs two models, after fully creating them based on their bases/imports,
     * then prints them out ot an HTML file.
     * @param ID1 - the ID for the first ModelTable
     * @param pathIn1 - the path for the first file to get input from.
     * @param ID2 - the ID for the second ModelTable
     * @param pathIn2 - the path for the second file to get input from.
     * @param fileOut - the file to output the HTML table to.
     * @param majorItemType - the type of item that defines a row.
     * @param cols - IHM of columns to use.
     * @return true if the conversion worked, false if not.
     * @throws Exception - upon most any error.
     */
    public ModelTable diffTwoTables(ColumnMap cols, String ID1, String pathIn1, String ID2, String pathIn2, File fileOut, String majorItemType) throws Exception
    {
        TablerController controller = new TablerController(cols);
        Doublet<String, Row> header = controller.getHeader();

        ModelTableDiffer differ = new ModelTableDiffer();

        ModelTable table1 = null, table2 = null, diffed = null;

        try
        {
            table1 = docToModelTable(cols, ID1, pathIn1, majorItemType);
            System.out.println("INFO: made table " + table1.getVersion());
            System.out.println();
        } catch (Exception ex)
        {
            Logger.getLogger(ThreepioEngine.class.getName()).log(Level.SEVERE, "could not document and table the first file.", ex);
            throw (ex);
        }

        try
        {
            table2 = docToModelTable(cols, ID2, pathIn2, majorItemType);
            System.out.println("INFO: made table " + table2.getVersion());
            System.out.println();
        } catch (Exception ex)
        {
            Logger.getLogger(ThreepioEngine.class.getName()).log(Level.SEVERE, "could not document and table the second file.", ex);
            throw (ex);
        }
        try
        {
            table1.makeStale();
            table2.makeStale();

            diffed = differ.diffTable(table1, table2, majorItemType, controller.verColNum());
            // System.err.println("diffed table now called " + diffed.getVersion());
        } catch (Exception ex)
        {
            Logger.getLogger(ThreepioEngine.class.getName()).log(Level.SEVERE, "could not diff the tables.", ex);
        }

        // another band-aid
        for (int i = 0; i < diffed.size(); i++)
        {
            if ((!(table2.containsKey(diffed.get(i).getKey()))) && ID1.contains(diffed.get(i).getValue().get(controller.verColNum()).getData()))
            {
                diffed.get(i).getValue().makeFresh();
            }
        }

        diffed.get(header.getKey()).makeStale();

        return diffed;
    }

    /**
     * Prints A ModelTable object to a file, based on the printer used.
     * @param table - the table to print.
     * @param printer - the FilePrinter to use to convert the table to file content.
     * @param fileOut - the file to print the ModelTable out to.
     * @param pre - text to go before the table
     * @param post - text to go after the table.
     * @param diff - if the diffing formatting should show or not.
     * @param looks - if the table should be formatted to have everything fit nicely on a page or webpage or not.
     * @return true if the print worked, false if not.
     * @throws Exception - when there are file problems.
     */
    public boolean printTable(XTable table, FilePrinter printer, File fileOut, String pre, String post, boolean diff, boolean looks) throws Exception
    {
        return (stringToFile(convertTable(table, printer, fileOut, pre, post, diff, looks), fileOut) != null);
    }

      /**
     * Converts a table to the output obtained using the printer passed.
     * @param table - the table to print.
     * @param printer - the FilePrinter to use to convert the table to file content.
     * @param fileOut - the file to print the ModelTable out to.
     * @param pre - text to go before the table
     * @param post - text to go after the table.
     * @param diff - if the diffing formatting should show or not.
     * @param looks - if the table should be formatted to have everything fit nicely on a page or webpage or not.
     * @return the String that the printer produces based on the table.
     * @throws Exception - when there are file problems.
     */
     public String convertTable(XTable table, FilePrinter printer, File fileOut, String pre, String post, boolean diff, boolean looks) throws Exception
     {
         
        StringBuffer buff = new StringBuffer();

        buff.append(pre);
        buff.append(printer.convertTable(table, diff, looks));
        buff.append(post);

        return buff.toString();
     }

     /**
      * Wraps a String with another file, and outputs it to a new file.
      * @param info - the string to wrap.
      * @param out - the file to write out to.
      * @param wrap - the file with the contents to wrap around the string.
      * @param placeHolder - the text that should be replaced by the string.
      * @return the File object for the file created by this method.
      * @throws Exception when IO errors occur.
      */
    public File wrapStringWithFile(String info, File out, File wrap, String placeHolder) throws Exception
    {
        String str = FileIntake.fileToString(wrap);

        str = str.replace(placeHolder, info);

        return stringToFile(str, out);
    }

    /**
     * Writes a string out to a the file passed.
     * @param s - the string to write out.
     * @param f - the File to write to.
     * @return the File passed, after processing.
     * @throws Exception when the output file is unwriteable or File object is null.
     */
    public File stringToFile(String s, File f) throws Exception
    {
        BufferedWriter writer = null;

        if (f == null)
        {
            throw new Exception("output file is null");
        }

        if (f.exists())
        {
            f.delete();
        }

        f.createNewFile();

        if (!f.canWrite())
        {
            throw new Exception("cannot output to file: " + f.getPath());
        }

        try
        {
            writer = new BufferedWriter(new FileWriter(f));
        } catch (IOException ex)
        {
            Logger.getLogger(ThreepioEngine.class.getName()).log(Level.SEVERE, "couldn't init writing to file", ex);
        }

        try
        {
            writer.write(s);
            writer.close();
        } catch (IOException ex)
        {
            Logger.getLogger(ThreepioEngine.class.getName()).log(Level.SEVERE, "could not write file", ex);
        }

        System.out.println("INFO: printing done.");
        System.out.println("\tFile Location: " + f.getPath());

        return f;
    }
}

