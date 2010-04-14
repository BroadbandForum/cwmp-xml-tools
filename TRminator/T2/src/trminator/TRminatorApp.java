/*
 * File: TRminatorApp.java
 * Project: TRminator
 * Author: Jeff Houle
 */
package trminator;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.logging.Level;
import java.util.logging.Logger;
import threepio.container.HashList;
import threepio.engine.ThreepioApp;
import threepio.engine.ThreepioEngine;
import threepio.filehandling.FileIntake;
import threepio.printer.HTMLPrinter;
import threepio.tabler.TablePostProcessor;
import threepio.tabler.container.ColumnMap;
import threepio.tabler.container.ModelTable;

/**
 * TRminatorApp is the main application of the TRminator.
 * It provides the user with access to both the graphical and command-line interfaces,
 * and is where the command-line interface is defined.
 * @author jhoule
 */
public class TRminatorApp extends ThreepioApp
{

    /**
     * the version of the application
     */
    public static final String appVersion = "-=JudgementDay=-\n (100329)";
    protected static final String strUseGui = "-gui", strUseCli = "-cli";
    protected static final boolean CLIMODE = Boolean.FALSE, GUIMODE = Boolean.TRUE;
    ////// Begin new UI work ////////////
    protected Boolean diff = Boolean.TRUE, diffingTwo = Boolean.FALSE, genericTable = Boolean.FALSE, prof = Boolean.FALSE, looks = Boolean.FALSE;
    protected String pathIn = null, pathTwo = null, pathOut = null, modelName = null, modelTwo = null, containerName = "Object";
    protected ColumnMap cols;
    protected File fIn = null, fTwo = null, fOut = null;
    protected int typeCol;
    protected TRminatorUI ui;
    private ThreepioEngine seeThree;

    public TRminatorApp()
    {
        seeThree = new ThreepioEngine();
    }

    // the option strings that require an argument.
    final static HashMap<String, Integer> OMap()
    {
        HashMap<String, Integer> map = new HashMap<String, Integer>();

        map.put("-i", 1);
        map.put("-ii", 1);
        map.put("-o", 1);
        map.put("-cols", 1);

        return map;
    }

    ////////// End new UI work ///////////////////////
    /**
     * the main function of TRminatorApp is to kick off the CLI or the GUI for the user,
     * and pass the arguments (save the interface definition) to that user interface.
     * It does not require command-line-arguments, but can take them.
     * If no arugments are provided, or the first is "-gui" the GUI is kicked off.
     * 
     * If the first arg is "-cli," the command-line interface is kicked off, and subsequent args are sent to it.
     * @param args - the command-line arguments.
     */
    public static void main(String args[])
    {
        HashList<String, String> userOpts = null;
        boolean uiMode;
        ArrayList<String> tempList;


        TRminatorApp app = new TRminatorApp();

        // map all options from command line arguments.
        try
        {
            userOpts = makeOptMap(args, OMap());
        } catch (Exception ex)
        {
            failBeforeInit("CommandLine argument parsing failed.", ex);
        }

        // determine UI choice

        uiMode = userOpts.containsKey(strUseCli);

        // find out if we're in the "diffingtwo" mode.
        app.diffingTwo = (userOpts.containsKey("-diffingtwo"));

        // find out if the looks are enabled.
        app.looks = userOpts.containsKey("-looks");

        // set diff option
        if (app.diffingTwo)
        {
            app.diff = true;
        } else
        {

            app.diff = (!userOpts.containsKey("-nodiff"));
        }

        // set prof option
        app.prof = (userOpts.containsKey("-includeprofiles"));

        try
        {
            tempList = null;

            // set pathOut option
            tempList = userOpts.get("-o");

            if (tempList != null)
            {
                app.pathOut = tempList.get(0);



            }

            tempList = null;

            // set pathIn option
            tempList = userOpts.get("-i");

            if (tempList != null)
            {
                app.pathIn = tempList.get(0);

            }

            tempList = null;

            // set second path option
            tempList = userOpts.get("-ii");

            if (tempList != null)
            {
                app.pathTwo = tempList.get(0);

            }


        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "could not parse options to variables", ex);
            failBeforeInit("could not parse options into essential variables", ex);
        }


        ////// we should have as much information as possible at this point.

        if (userOpts.containsKey("-cols"))
        {
            try
            {
                File f = new File(userOpts.get("-cols").get(0));
                app.cols = TRCols.loadFromFile(f);
            } catch (Exception ex)
            {
                failBeforeInit("issue loading custom cols", ex);
            }
        } else
        {
            // set up the default columns.
            app.cols = TRCols.getDefaultColMap();
        }



        // make UI.

        if (uiMode)
        {
            app.ui = new TRminatorCLI(app);
        } else
        {
            app.ui = new TRminatorGUI(app);
        }
        try
        {
            // init ui
            app.ui.init();
        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, null, ex);
            failBeforeInit("could not initiailize ui");
        }

        //app.ui.run();

        new Thread(app.ui).start();
    }

    protected void collectFiles()
    {
        boolean okay = true;

        try
        {
            fIn = getIn(pathIn);
        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "cannot continue without input file", ex);
            ui.fail("error while parsing input file", ex);
            okay = false;
        }

        pathIn = fIn.getPath();

        if (diffingTwo)
        {
            try
            {
                fTwo = getIn(pathTwo);
            } catch (Exception ex)
            {
                Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "cannot continue without input file #2", ex);
                ui.fail("error while parsing input file #2", ex);
                okay = false;
            }

            pathTwo = fTwo.getPath();
        }


        if (okay)
        {
            ui.updateFields("files located");
        } else
        {
            ui.updateFields("could not load files.\ncorrect errors and try again.");
        }


    }

    protected boolean doChecks()
    {
        String depends;
        // get the model name for the resulting table.
        try
        {
            modelName = ui.getModel(fIn);
            

            if (diffingTwo)
            {
                modelTwo = ui.getModel(fTwo);

                if (modelTwo == null)
                {
                    ui.fail("no model name selected for input 2");
                    return false;
                }
            }

            if (modelName == null)
            {
                ui.fail("no model name selected for input\nIt is possible that there are none.");
                return false;
            }

        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "cannot continue without knowing model name", ex);
            ui.fail("could not obtain a valid model name", ex);
            return false;
        }

        

        // check to make sure no required files are missing.
        depends = new String();
        seeThree = new ThreepioEngine();
        try
        {
            depends = seeThree.getMissingDepends(pathIn, modelName);

            if (diffingTwo)
            {
                depends += "\n" + seeThree.getMissingDepends(pathTwo, modelTwo);
            }

        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "depdencies are missing.", ex);
            ui.fail("missing some files the model is dependent on", ex);
            return false;

        }

        if (!depends.trim().isEmpty())
        {
            ui.fail("There are files missing:\n" + depends);
            return false;
        }

        ui.updateStatusMsg("files inspected and approved");
        return true;
    }

    protected void makeTable()
    {
        ModelTable table;
        TablePostProcessor processor;
        HTMLPrinter printer;


        // create File object for output file.
        try
        {
            fOut = getOut(pathOut);
        } catch (IOException ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "error creating file", ex);
            ui.fail("could not initailize all required files", ex);
        }

        // make the table
        try
        {
            if (genericTable)
            {
                printer = new HTMLPrinter();
                try
                {
                    seeThree.xmlToPrintedModelTable(cols, printer, "", pathIn, fOut);
                } catch (Exception ex)
                {
                    ui.fail("could not make generic table", ex);
                }

                ui.updateStatusMsg("Table printed\nAvailable at: " + fOut.getAbsolutePath());
            } else
            {

                typeCol = getTypeCol();

                if (diffingTwo)
                {
                    table = seeThree.diffTwoTables(cols, modelName, pathIn,
                            modelTwo, pathTwo, fOut, "Object");
                } else
                {
                    table = seeThree.docToModelTable(cols, modelName, pathIn, "Object");
                }

                ui.updateStatusMsg("Table created");

                processor = new TablePostProcessor();

                processor.deMarkupTable(table, new File(fOut.getParent() + FileIntake.fileSep + "post.err"), typeCol);
                seeThree.printModelTable(table, fOut, diff, prof, looks);

                ui.updateStatusMsg("Table printed\nAvailable at: " + fOut.getAbsolutePath());
            }
        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorCLI.class.getName()).log(Level.SEVERE, "Could not make table", ex);
            ui.fail("Could not make table:\n\t" + ex.getMessage(), ex);
        }
    }

    /**
     * Provides failure information in the console then quits with error code.
     * @param msg - the message to give to the user
     * @param ex - an Exception to include in the failure information.
     */
    private static void failBeforeInit(String msg, Exception ex)
    {
        Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, msg, ex);
        System.err.println(msg);
        System.err.println(ex.getMessage());
        ex.printStackTrace();
        System.exit(-1);
    }

    /**
     * Provides failure information in the console then quits with error code.
     * @param msg - the message to give to the user
     */
    private static void failBeforeInit(String msg)
    {
        System.err.println(msg);
        System.exit(-1);
    }

    /**
     * returns the column index for the one that defines the type of an item.
     * @return the index of the type column.
     */
    public int getTypeCol()
    {
        int c;

        c = cols.indexByKeyOf("Type");

        if (c < 0)
        {
            return cols.indexByKeyOf("type");
        }

        return c;
    }
}
