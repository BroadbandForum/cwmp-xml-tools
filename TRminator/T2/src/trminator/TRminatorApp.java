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
    public static final String appVersion = "JudgementDay (100318";
    protected static final String strUseGui = "-gui", strUseCli = "-cli";
    protected static final boolean CLIMODE = Boolean.FALSE, GUIMODE = Boolean.TRUE;
    ////// Begin new UI work ////////////
    protected Boolean diff = Boolean.TRUE, diffingTwo = Boolean.FALSE, prof = Boolean.FALSE, looks = Boolean.FALSE;
    protected String pathIn = null, pathTwo = null, pathOut = null, modelName = null, modelTwo = null;
    protected ColumnMap cols;
    protected File fIn = null, fTwo = null, fOut = null;
    protected int typeCol;
    protected TRminatorUI ui;

    // the option strings that require an argument.
    final static HashMap<String, Integer> OMap()
    {
        HashMap<String, Integer> map = new HashMap<String, Integer>();

        map.put("-i", 1);
        map.put("-ii", 1);
        map.put("-o", 1);

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
        ThreepioEngine seeThree;

        HashList<String, String> userOpts = null;
        boolean uiMode;
        ArrayList<String> tempList;
        String depends;

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

                // create File object for output file.
                try
                {
                    app.fOut = app.ui.getOut(app.pathOut);
                } catch (IOException ex)
                {
                    Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "error creating file", ex);
                    failBeforeInit("could not initailize all required files", ex);
                }

            }

            tempList = null;

            // set pathIn option
            tempList = userOpts.get("-i");

            if (tempList != null)
            {
                app.pathIn = tempList.get(0);
                try
                {
                    app.fIn = getIn(app.pathIn);
                } catch (Exception ex)
                {
                    Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "cannot continue without input file", ex);
                    failBeforeInit("error while parsing input file");
                }
            }

            tempList = null;

            // set second path option
            tempList = userOpts.get("-ii");

            if (tempList != null)
            {
                if (app.diffingTwo && app.pathTwo != null)
                {
                    try
                    {
                        app.fTwo = getIn(app.pathTwo);
                    } catch (Exception ex)
                    {
                        Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "cannot continue without input file #2", ex);
                        failBeforeInit("error while parsing input file #2");
                    }
                }
            }


        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "could not parse options to variables", ex);
            failBeforeInit("could not parse options into essential variables", ex);
        }


        // get the model name for the resulting table.
        try
        {
            app.modelName = app.ui.getModel(app.fIn);

            if (app.diffingTwo)
            {
                app.modelTwo = app.ui.getModel(app.fTwo);

                if (app.modelTwo == null)
                {
                    failBeforeInit("no model name selected for input 2");
                }
            }

            if (app.modelName == null)
            {
                failBeforeInit("no model name selected for input");
            }

        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "cannot continue without knowing model name", ex);
            failBeforeInit("could not obtain a valid model name", ex);
        }

        ////// we should have as much information as possible at this point.

        // set up the default columns.
        app.cols = TRCols.getDefaultColMap();

        // check to make sure no required files are missing.

        depends = new String();
        seeThree = new ThreepioEngine();
        try
        {
            depends = seeThree.getMissingDepends(app.pathIn, app.modelName);

            if (app.diffingTwo)
            {
                depends += "\n" + seeThree.getMissingDepends(app.pathTwo, app.modelTwo);
            }

        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "depdencies are missing.", ex);
            app.ui.fail("missing some files the model is dependent on", ex);
        }

        if (!depends.trim().isEmpty())
        {
            app.ui.fail("There are files missing:\n" + depends);
        }
    }

    private static void makeTable(TRminatorApp app, ThreepioEngine seeThree)
    {
        ModelTable table;
        TablePostProcessor processor;

        // make the table
        try
        {
            app.typeCol = app.cols.indexByKeyOf("Type");

            if (app.typeCol < 0)
            {
                app.typeCol = app.cols.indexByKeyOf("type");
            }

            if (app.diffingTwo)
            {
                table = seeThree.diffTwoTables(app.cols, app.modelName, app.pathIn,
                        app.modelTwo, app.pathTwo, app.fOut, "Object");
            } else
            {
                table = seeThree.docToModelTable(app.cols, app.modelName, app.pathIn, "Object");
            }

            processor = new TablePostProcessor();

            processor.deMarkupTable(table, new File(app.fOut.getParent() + FileIntake.fileSep + "post.err"), app.typeCol);
            seeThree.printModelTable(table, app.fOut, app.diff, app.prof, app.looks);

        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorCLI.class.getName()).log(Level.SEVERE, "Could not make table", ex);
            app.ui.fail("Could not make table:\n\t" + ex.getMessage(), ex);
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
}

