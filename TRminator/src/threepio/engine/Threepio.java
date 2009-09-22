/*
 * File: Threepio.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.engine;

import threepio.container.Doublet;
import threepio.documenter.XDoc;
import threepio.documenter.XDocumenter;
import threepio.filehandling.FileIntake;
import threepio.filehandling.Importer;
import java.io.*;
import java.util.Iterator;
import java.util.Map.Entry;
import java.util.Stack;
import java.util.logging.Level;
import java.util.logging.Logger;
import threepio.tabler.*;
import threepio.tabler.container.*;
import threepio.printer.HTMLPrinter;

/**
 * The Threepio class is the high-level processor for XML/BBF Data Model processing
 * and diffing.
 *
 * It should be controlled by a separate UI, like ThreepioFrame.
 *
 * @author jhoule
 * @see trminator.TRminatorGUI
 */
public class Threepio
{

    /**
    docToPrintedTable turns an XDoc object into a ModelTable object, and prints it out
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
    public static boolean docToPrintedTable(IndexedHashMap<String, String> cols, String ID, String pathIn, File fileOut, String majorItemType, boolean diff, boolean profiles, boolean looks) throws Exception
    {
        return printModelTable(docToTable(cols, ID, pathIn, majorItemType), fileOut, diff, profiles, looks);
    }

    /**
     *
     * @param cols - an IHM of the columns to use for the table.
     * @param ID - the ID of the body in the file to put into the ModelTable.
     * @param pathIn - the path for the file to examine.
     * @param majorItemType - the type of item that defines a row
     * @return the table based on the input.
     * @throws Exception - in the case of any error returned by subroutines.
     */
    public static ModelTable docToTable(IndexedHashMap<String, String> cols, String ID, String pathIn, String majorItemType) throws Exception
    {
        ModelTable table = null;
        TablerController controller = new TablerController(cols);

        try
        {
            table = controller.makeWholeTable(ID, pathIn, majorItemType, true);

        } catch (Exception ex)
        {

            Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "problem making table", ex);
            throw (ex);
        }

        return table;
    }

    /**
     * (experimental) xmlToPrintedTable makes any XML file with a sound heiarchy
     * into an HTML table.
     * @param ID - name of object to table
     * @param pathIn - the path for the file to use as input.
     * @param fileOut - the file to output the table to.
     * @param cols - IHM of columns to use.
     * @return true if the conversion worked, false if not.
     * @throws Exception - upon most any error.
     */
    public static boolean xmlToPrintedTable(IndexedHashMap<String, String> cols, String ID, String pathIn, File fileOut) throws Exception
    {
        return printTable((ModelTable) xmlToTable(cols, ID, pathIn), fileOut);
    }

    /**
     * xmlToTable converts a chunk of XML data to an XTable
     * @param cols - an IHM of the columns the table should have.
     * @param ID - the version or ID for the Table.
     * @param pathIn - the path of the input file.
     * @return - the XML information as a simple Table.
     * @throws Exception - when there is a problem converting.
     * @see XTable
     */
    private static XTable xmlToTable(IndexedHashMap<String, String> cols, String ID, String pathIn) throws Exception
    {
        ModelTabler xTabler = new ModelTabler(cols);
        XDocumenter documenter = new XDocumenter();

        XTable table = null;

        File file = FileIntake.resolveFile(new File(pathIn));

        try
        {
            table = (ModelTable) xTabler.parseContainer(documenter.convertFile(file), "name", ID, true);
            table.put(0, xTabler.getHeader());
        } catch (Exception ex)
        {
            Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "could not document and table the file.", ex);
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
    public static ModelTable diffTwoTables(IndexedHashMap<String, String> cols, String ID1, String pathIn1, String ID2, String pathIn2, File fileOut, String majorItemType) throws Exception
    {
        TablerController controller = new TablerController(cols);
        Doublet<String, Row> header = controller.getHeader();

        ModelTableDiffer differ = new ModelTableDiffer();

        ModelTable table1 = null, table2 = null, diffed = null;

        try
        {
            table1 = docToTable(cols, ID1, pathIn1, majorItemType);
            System.out.println("made table " + table1.getVersion());
        } catch (Exception ex)
        {
            Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "could not document and table the first file.", ex);
            throw (ex);
        }

        try
        {
            table2 = docToTable(cols, ID2, pathIn2, majorItemType);
            System.out.println("made table " + table2.getVersion());
        } catch (Exception ex)
        {
            Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "could not document and table the second file.", ex);
            throw (ex);
        }
        try
        {
            table1.makeStale();
            table2.makeStale();

            diffed = differ.diffTable(table1, table2, majorItemType, controller.verColNum());
            System.out.println("diffed table now called " + diffed.getVersion());
        } catch (Exception ex)
        {
            Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "could not diff the tables.", ex);
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
     * shortcut for print table, where diffing is not involved.
     * @param table - the table to print out.
     * @param fileOut - the file to print the ModelTable out to.
     * @return true if the print worked, false if not.
     */
    private static boolean printTable(XTable table, File fileOut) throws Exception
    {
        return printTable(table, fileOut, false, false);
    }

    /**
     * Prints A ModelTable object to a file, in HTML.
     * @param table - the table to print.
     * @param fileOut - the file to print the ModelTable out to.
     * @param diff - if the diffing formatting should show or not.
     * @param looks - if the table should be formatted to have everything fit nicely on a page or webpage or not.
     * @return true if the print worked, false if not.
     * @throws Exception - when there are file problems.
     */
    public static boolean printTable(XTable table, File fileOut, boolean diff, boolean looks) throws Exception
    {
        BufferedWriter writer;
        HTMLPrinter printer = new HTMLPrinter();
        StringBuffer buff = new StringBuffer();
        XTable biblio = null;

        if (table instanceof ModelTable)
        {
            biblio = ((ModelTable) table).getBiblio();
        }

        buff.append("<html>\n<head><title>" + table.getVersion() + "</title></head>\n");
        buff.append(printer.convertTable(table, diff, looks));
        if (biblio != null)
        {
            buff.append("\n<br><br>");
            buff.append("<STRONG>REFERENCES:</STRONG>\n");
            buff.append(printer.convertTable(biblio));
        }

        buff.append("</html>");
        try
        {
            writer = new BufferedWriter(new FileWriter(fileOut));
        } catch (IOException ex)
        {
            Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "couldn't init writing to file", ex);
            return false;
        }
        try
        {
            writer.write(buff.toString());
            writer.close();
        } catch (IOException ex)
        {
            Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "could not write file", ex);
            return false;
        }

        System.out.println("printing done.");
        return true;
    }

    /**
     * Prints a table much like printTable, but adds references and Profiles, if found.
     * @param table - the table to print.
     * @param fileOut - the file to print out to.
     * @param diff - a boolean that determines wether or not diffing information shoud appear on output.
     * @param profiles - tells it whether to append a table of Model items from doc(s)
     * @param looks - if the table should be formatted to have everything fit nicely on a page or webpage or not.
     * @return true if the table printed alright.
     * @throws Exception - when something goes wrong in printing.
     */
    public static boolean printModelTable(ModelTable table, File fileOut, boolean diff, boolean profiles, boolean looks) throws Exception
    {
        BufferedWriter writer;
        HTMLPrinter printer = new HTMLPrinter();
        StringBuffer buff = new StringBuffer();
        XTable biblio = null, profs = null;

        if (table instanceof ModelTable)
        {
            biblio = ((ModelTable) table).getBiblio();
            profs = ((ModelTable) table).getProfiles();
        }
        buff.append("<html>\n<head><title>" + table.getVersion() + "</title></head>\n");
        buff.append(printer.convertTable(table, diff, looks));

        if (profs != null && !profs.isEmpty() && profiles)
        {

            buff.append("\n<br><br>");
            buff.append("<STRONG>Profiles:</STRONG>\n");

            profs.StripEmptyCols();

            buff.append(printer.convertTable(profs, false, looks));
        }

        if (biblio != null)
        {
            buff.append("\n<br><br>");
            buff.append("<STRONG>REFERENCES:</STRONG>\n");
            buff.append(printer.convertTable(biblio, false, looks));
        }


        buff.append("</html>");
        try
        {
            writer = new BufferedWriter(new FileWriter(fileOut));
        } catch (IOException ex)
        {
            Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "couldn't init writing to file", ex);
            return false;
        }
        try
        {
            writer.write(buff.toString());
            writer.close();
        } catch (IOException ex)
        {
            Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "could not write file", ex);
            return false;
        }

        System.out.println("printing done.");
        return true;
    }

    /**
     * gets a list of missing depdendencies (files) for a model, in a file.
     * @param path - the path for the file to use.
     * @param modelName - the model to get the files for.
     * @return a string of file paths, one per line.
     * @throws Exception - when files are not found or there is an IO error.
     *
     */
    public static String getMissingDepends(String path, String modelName) throws Exception
    {

        XDocumenter doccer = new XDocumenter();
        StringBuffer buff = new StringBuffer();
        XDoc doc = null;
        boolean canDoc = true;
        Importer importer = new Importer();
        Iterator<Entry<String, String>> it;
        String workPath, oldPath;
        File file;
        Entry<String, String> tempEnt1;
        Entry<String, File> tempEnt2;
        Stack<Entry<String, File>> files = new Stack<Entry<String, File>>();

        file = FileIntake.resolveFile(new File(path));

        if (file == null)
        {
            throw new FileNotFoundException("Cannot list dependencies because cannot locate original file");
        }

        String curModel = modelName;

        workPath = file.getParent();
        files.add(new Doublet<String, File>(curModel, file));

        // go through files.
        while (!files.isEmpty())
        {
            tempEnt2 = files.pop();
            file = tempEnt2.getValue();

            canDoc = true;
            importer = new Importer();

            curModel = tempEnt2.getKey();

            oldPath = file.getPath();


            if (FileIntake.canResolveFile(file))
            {
                try
                {
                    doc = doccer.convertFile(new Doublet(curModel, file.getPath()));

                } catch (Exception ex)
                {
                    doc = null;
                    canDoc = false;
                }

                if (canDoc)
                {
                    try
                    {
                        importer.importFrom(doc, curModel);
                    } catch (Exception ex)
                    {
                        Logger.getLogger(Threepio.class.getName()).log(Level.SEVERE, "importer failure", ex);
                        throw (ex);
                    }

                    it = importer.getToTable().entrySet().iterator();
                    while (it.hasNext())
                    {
                        tempEnt1 = it.next();
                        file = FileIntake.resolveFile(new File(workPath + FileIntake.fileSep + tempEnt1.getValue()));

                        if (file == null)
                        {
                            buff.append(oldPath + "\n");
                        } else
                        {

                            files.add(new Doublet<String, File>(tempEnt1.getKey(), file));
                            curModel = tempEnt1.getKey();
                        }
                    }
                }
            } else
            {
                buff.append(oldPath + "\n");
            }
        }

        if (importer.hasBiblio())
        {
            file = FileIntake.resolveFile(new File(workPath + FileIntake.fileSep + importer.getBiblio()));
            oldPath = workPath + FileIntake.fileSep + importer.getBiblio();

            if (file == null)
            {
                buff.append(oldPath);
            }
        }
        return buff.toString();
    }
}
