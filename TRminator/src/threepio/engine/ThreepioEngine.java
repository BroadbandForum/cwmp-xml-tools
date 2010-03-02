/*
 * File: ThreepioEngine.java
 * Project: ThreepioEngine
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
import threepio.printer.HTMLPrinter;
import threepio.tabler.container.ModelTable;
import threepio.tabler.container.XTable;

/**
 * The ThreepioEngine class is the high-level processor for XML/BBF Data Model processing
 * and diffing.
 *
 * It should be controlled by a separate UI, like ThreepioFrame.
 *
 * @author jhoule
 * @see trminator.TRminatorGUI
 */
public class ThreepioEngine extends Engine
{

    /**
     * gets a list of missing depdendencies (files) for a model, in a file.
     * @param path - the path for the file to use.
     * @param modelName - the model to get the files for.
     * @return a string of file paths, one per line.
     * @throws Exception - when files are not found or there is an IO error.
     *
     */
    public String getMissingDepends(String path, String modelName) throws Exception
    {

        XDocumenter doccer = new XDocumenter();
        StringBuffer buff = new StringBuffer();
        XDoc doc = null;
        boolean canDoc = true;
        Importer importer = new Importer();
        Iterator<Entry<String, String>> it;
        String workPath, oldPath, thePath;
        File file;
        Entry<String, String> tempEnt1;
        Entry<String, File> tempEnt2;
        Stack<Entry<String, File>> files = new Stack<Entry<String, File>>();

        file = FileIntake.resolveFile(new File(path), true);

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
                    doc = doccer.convertFile(new Doublet<String, String>(curModel, file.getPath()));

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
                        Logger.getLogger(ThreepioEngine.class.getName()).log(Level.SEVERE, "importer failure", ex);
                        throw (ex);
                    }

                    it = importer.getToTable().entrySet().iterator();
                    while (it.hasNext())
                    {
                        tempEnt1 = it.next();
                        thePath = workPath + FileIntake.fileSep + tempEnt1.getValue();
                        file = FileIntake.resolveFile(new File(thePath), true);

                        if (file == null)
                        {
                            buff.append(thePath + "\n");
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
            file = FileIntake.resolveFile(new File(workPath + FileIntake.fileSep + importer.getBiblio()), true);
            oldPath = workPath + FileIntake.fileSep + importer.getBiblio();

            if (file == null)
            {
                buff.append(oldPath);
            }
        }
        return buff.toString();
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
    @Override
    public boolean printModelTable(ModelTable table, File fileOut, boolean diff, boolean profiles, boolean looks) throws Exception
    {
        HTMLPrinter printer = new HTMLPrinter();
        StringBuffer buffPre = new StringBuffer(), buffPost = new StringBuffer();
        XTable biblio = null, profs = null;


        biblio = table.getBiblio();
        profs = table.getProfiles();

        buffPre.append("<html>\n<head><title>" + table.getVersion() + "</title></head>\n");

        if (profs != null && !profs.isEmpty() && profiles)
        {

            buffPost.append("\n<br><br>");
            buffPost.append("<STRONG>Profiles:</STRONG>\n");

            profs.StripEmptyCols();

            buffPost.append(printer.convertTable(profs, false, looks));
        }

        if (biblio != null)
        {
            buffPost.append("\n<br><br>");
            buffPost.append("<STRONG>REFERENCES:</STRONG>\n");
            buffPost.append(printer.convertTable(biblio, false, looks));
        }


        buffPost.append("</html>");

        return printTable(table, printer, fileOut, buffPre.toString(), buffPost.toString(), diff, looks);
    }
}
