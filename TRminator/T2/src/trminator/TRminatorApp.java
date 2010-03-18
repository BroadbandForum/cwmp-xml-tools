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
import threepio.tabler.TablePostProcessor;
import threepio.tabler.container.ColumnMap;

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
    public static final String appVersion = "TRminator RC5 (100301)";
    protected static final String strUseGui = "-gui", strUseCli = "-cli";
    protected static final boolean CLIMODE = Boolean.FALSE, GUIMODE = Boolean.TRUE;
    ////// Begin new UI work ////////////
    protected Boolean diff = Boolean.TRUE, diffingTwo = Boolean.FALSE, prof = Boolean.FALSE, looks = Boolean.FALSE;
    protected String pathIn = null, pathTwo = null, pathOut = null, modelName = null, modelTwo = null, depends = new String();
    protected ColumnMap cols;
    protected File fIn = null, fTwo = null, fOut = null;
    protected TablePostProcessor processor = new TablePostProcessor();
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

        ////// we should have as much information as possible from this.


//        String[] newArgs;
//        int mode = -1;
//
//        switch (args.length)
//        {
//            case 0:
//            {
//                // no arguments, so open up a GUI.
//                TRminatorGUIPanel.main(appVersion, null);
//                break;
//            }
//
//            default:
//            {
//                mode = getMode(args[0]);
//                newArgs = new String[args.length - 1];
//
//                for (int i = 1; i < args.length; i++)
//                {
//                    newArgs[i - 1] = args[i];
//                }
//
//                switch (mode)
//                {
//                    case 0:
//                    {
//                        // using the gui, pass arguments on, except first.
//                        TRminatorGUIPanel.main(appVersion, newArgs);
//                        break;
//                    }
//
//                    case 1:
//                    {
//
//                        if (newArgs.length < 1)
//                        {
//                            System.err.println("ERROR: No arguments found for CLI mode!");
//                        } else
//                        {
//                            try
//                            {
//                                TRminatorCLI.main(newArgs);
//
//                            } catch (Exception ex)
//                            {
//                                Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "the CLI exited unexpectedly.", ex);
//                                System.err.println("ERROR: CLI exited unhappily");
//                            }
//                        }
//                        break;
//                    }
//                    default:
//                    {
//                        System.err.println("ERROR: unknown mode (Did you forget to specify it in the first argument?)\nQuitting");
//                    }
//                }
//            }
//        }
    }

    /**
     * getMode returns an int that the UI mode can be identified by.
     * It searches the modes array for the string passed.
     * @param str - the string for the desired mode.
     * @return the int that corresponds with the mode, or -1 if it's not a known mode.
     */
    @SuppressWarnings("empty-statement")
    private static int getMode(String str)
    {
        int i = 0;
        for (i = 0; i < modes.length && modes[i].compareTo(str) != 0; i++);

        if (i >= modes.length)
        {
            return -1;
        }

        return i;
    }

    private static void failBeforeInit(String msg, Exception ex)
    {
        Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, msg, ex);
        System.err.println(msg);
        System.err.println(ex.getMessage());
        ex.printStackTrace();
        System.exit(-1);
    }

    private static void failBeforeInit(String msg)
    {
        System.err.println(msg);
        System.exit(-1);
    }
}

