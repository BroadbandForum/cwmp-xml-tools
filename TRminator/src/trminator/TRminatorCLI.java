/*
 * File: TRminatorCLI.java
 * Project: TRminator
 * Author: Jeff Houle
 */
package trminator;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Scanner;
import java.util.logging.*;
import threepio.documenter.XDocumenter;
import threepio.engine.Threepio;
import threepio.filehandling.FileIntake;
import threepio.tabler.container.IndexedHashMap;
import threepio.tabler.container.ModelTable;

/**
 * TRminatorCLI defines a command-line interface for TRminator.
 * @author jhoule
 */
public class TRminatorCLI
{
    // the option strings that require an argument.

    private static final String[] optionsWithArgs =
    {
        "-i", "-o", "-ii"
    };

    /**
     * The main function of TRminatorCLI is to provide a command-line interface
     * for creating HTML tables, in files, from XML Data Models, like those made by
     * the BBF.
     * @param args - command-line arguments.
     */
    public static void main(final String appVersion, String args[])
    {
        // instance variables.
        Boolean diff = Boolean.TRUE, diffingTwo = Boolean.FALSE, prof = Boolean.FALSE, looks = Boolean.FALSE;
        String pathIn = null, pathTwo = null, pathOut = null, modelName = null, modelTwo = null, depends = new String();
        HashMap<String, String> userOpts = null;
        IndexedHashMap<String, String> cols = new IndexedHashMap<String, String>();
        File fIn = null, fTwo = null, fOut = null;
        ModelTable table;
        TablePostProcessor processor = new TablePostProcessor();
        int typeCol;

        // set up the default columns.
        setupCols(cols);
        System.out.println(appVersion + " is starting...");

        try
        {
            userOpts = makeOptMap(args);
        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "cannot continue without options", ex);
            fail("could not map user options");
        }
        try
        {
            // set pathOut option
            if (!userOpts.containsKey("-o"))
            {
                throw new Exception("no output file selected!");
            }
            pathOut = new String(userOpts.get("-o"));

            // set pathIn option
            if (!userOpts.containsKey("-i"))
            {
                throw new Exception("no input file selected!");
            }
            pathIn = userOpts.get("-i");

            pathTwo = userOpts.get("-ii");



            // find out if we're in the "diffingtwo" mode.
            diffingTwo = (userOpts.containsKey("-diffingtwo"));

            // find out if the looks are enabled.
            looks = userOpts.containsKey("-looks");

            // set diff option
            if (diffingTwo)
            {
                diff = true;
            } else
            {
                
                diff = (!userOpts.containsKey("-nodiff"));
            }

            // set prof option
            prof = (userOpts.containsKey("-includeprofiles"));

        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "could not parse options to variables", ex);
            fail("could not parse options into essential variables");
        }

        // create File object for input file.
        fIn = getIn(pathIn);

        if (diffingTwo && pathTwo != null)
        {
            fTwo = getIn(pathTwo);
        }

        // create File object for output file.
        try
        {
            fOut = getOut(pathOut);

        } catch (IOException ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "error creating file", ex);
            fail("could not initailize all required files");
        }

        // get the model name for the resulting table.
        try
        {
            modelName = getModel(fIn);

            if (diffingTwo)
            {
                modelTwo = getModel(fTwo);

                if (modelTwo == null)
                {
                    fail ("no model name selected for input 2");
                }
            }

            if (modelName == null)
            {
                fail("no model name selected for input");
            }

        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "cannot continue without knowing model name", ex);
            fail("could not obtain a valid model name");
        }

        // check to make sure no required files are missing.
        try
        {
            depends = Threepio.getMissingDepends(pathIn, modelName);
            
            if (diffingTwo)
            {
                depends += "\n" + Threepio.getMissingDepends(pathTwo, modelTwo);
            }

        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "dependancies are missing.", ex);
            fail("missing some files the model is dependent on");
        }

        if (!depends.trim().isEmpty())
        {
            fail("There are files missing:\n" + depends);
        }

        // make the table
        try
        {
            typeCol = cols.indexByKeyOf("Type");

            if (typeCol < 0)
            {
                typeCol = cols.indexByKeyOf("type");
            }

            if (userOpts.containsKey("-diffingtwo"))
            {
                table = Threepio.diffTwoTables(cols, modelName, pathIn, modelTwo, pathTwo, fOut, "Object");
            } else
            {
                table = Threepio.docToTable(cols, modelName, pathIn, "Object");               
            }
            processor.deMarkupTable(table, new File(fOut.getParent() + FileIntake.fileSep + "post.err"), typeCol);
            Threepio.printModelTable(table, fOut, diff, prof, looks);



        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorCLI.class.getName()).log(Level.SEVERE, "Could not make table", ex);
        }
    }

    /**
     * fail is a method for quitting unexpectedly, and reporting a reason to the user.
     * @param reason - the reason to give to the user.
     */
    private static void fail(String reason)
    {
        System.err.println("ERROR: " + reason + " \nnow quitting.");

        System.exit(1);
    }

    /**
     * getModel returns a string for the model's name, within a BBF document.
     * if there are multiple models, the user is prompted to choose one or exit.
     * @param fIn - the input file to scour for models.
     * @return the name of the model found or chosen
     * @throws Exception when the XDocumenter has a problem getting model names.
     * @see XDocumenter#getModelNames(java.io.File)
     */
    private static String getModel(File fIn) throws Exception
    {
        // instance variables
        XDocumenter doccer = new XDocumenter();
        Scanner scan;
        String userInput;
        Integer choice;
        ArrayList<String> models;

        // use the XDocumenter to get the names of models in the file.
        models = doccer.getModelNames(fIn);

        switch (models.size())
        {
            case 0:
            {
                // no models found.
                throw new Exception(fIn.getName() + " doesn't contain any noticeable models.");
            }

            case 1:
            {
                // there's only one model. return it.
                return models.get(0);
            }

            default:
            {
                // need to prompt user for which model.
                Boolean done = false;

                while (!done)
                {
                    System.out.println("Multiple Models exist in " + fIn.getName() +
                            "\nPlease Choose via number, or exit with 0.");

                    // list them
                    for (int i = 0; i < models.size(); i++)
                    {
                        System.out.println((i + 1) + " " + models.get(i));
                    }

                    // prompt for choice.
                    System.out.print(">");
                    scan = new Scanner(System.in);
                    userInput = scan.nextLine();

                    choice = null;
                    choice = Integer.parseInt(userInput);

                    if (choice == null)
                    {
                        done = false;
                        System.out.println("non-numerical answer. please try again.");

                    } else
                    {
                        switch (choice)
                        {
                            case 0:
                            {
                                // exiting
                                done = true;
                                System.exit(0);
                                break;
                            }

                            default:
                            {
                                // not exiting
                                if (choice <= models.size())
                                {
                                    // the user has a valid choice.
                                    done = true;
                                    return models.get(choice - 1);
                                }
                            }
                        }
                    }
                }
            }
        }
        // never actually gets here (the list cant' have a size <0.
        return null;
    }

    /**
     * getIn returns a File for the input file chosen by the user.
     * the program will exit if the path is incorrect, or the file is not readable.
     * @param pathIn - the path to the real file.
     * @return a File for the input.
     */
    private static File getIn(String pathIn)
    {
        // make File object for input
        File fIn = new File(pathIn);

        if (fIn == null || !fIn.exists())
        {
            fail("Input file " + pathIn + " does not exist");
        }

        if (!fIn.isFile())
        {
            fail("The input file " + pathIn + " is a directory.");
        }

        if (!fIn.canRead())
        {
            fail("Input file " + pathIn + " is not readable. Check to see if it is open.");
        }

        return fIn;
    }

    /**
     * getOut returns a File for the output file chosen by the user.
     * an existent file at given path will get deleted in the process.
     * @param pathOut - the path for the output file, as provided by the user.
     * @return a File for putting the output into.
     * @throws IOException when the file management experiences an issue.
     */
    private static File getOut(String pathOut) throws IOException
    {
        // make a file for output.
        File fOut = new File(pathOut);

        if (fOut.exists() && !fOut.isFile())
        {
            fail("The output file is a directory.");
        }

        // delete any file that exists there.
        if (fOut.exists())
        {
            fOut.delete();
        }

        // make a new file here.
        fOut.createNewFile();

        return fOut;
    }

    /**
     * setupCols fills the passed IndexedHashMap with the default values for columns, after emptying it.
     * @param cols - the IHM to fill up.
     */
    private static void setupCols(IndexedHashMap cols)
    {
        cols.clear();

        cols.put("Name", "name");
        cols.put("Type", "syntax");
        cols.put("Write", "access");
        cols.put("Description", "description");
        cols.put("Default", "default");
        cols.put("Version", "version");
    }

    /**
     * makeOptMap parses a String array into a HashMap.
     * If an option requires an argument, the argument is the value to a key with that option.
     * if the option does not require an argument, the key gets put on the map, with "true" as it's value.
     * these "true" values are not currently in use.
     *
     * Options MUST start with a '-' character.
     * Consequentially, arguments to options MUST NEVER start with a '-' character.
     *
     * @param opts - an arary of strings that represents the user's options.
     * @return a HashMap of the user's selections.
     * @throws Exception when an error in user input is found.
     */
    private static HashMap<String, String> makeOptMap(String[] opts) throws Exception
    {
        HashMap<String, String> map = new HashMap<String, String>();
        String key, val;
        int sz = opts.length, difference;

        for (int i = 0; i < sz; i++)
        {
            difference = sz - i;
            key = opts[i].toLowerCase();

            if (!key.startsWith("-"))
            {
                // all options should start with the dash.
                throw new Exception("invalid option: " + key);
            }

            if (needsArgument(key))
            {
                if (difference < 2)
                {
                    // this option cannot be used without a following argument.
                    throw new Exception("no arugment for option" + key);
                }

                // make lower case.
                val = opts[++i].toLowerCase();

                if (val.startsWith("-"))
                {
                    // it appears that another option is in the place of an argument for a previous option.
                    throw new Exception("no arugment for option" + key);
                }

                map.put(key, val);
            } else
            {
                // this option doesn't need an argument.
                // it's presence as a key on the map will be used in the program,
                // not it's value, but we put on a value of "true" just in case.
                map.put(key, "true");
                
            }
        }

        return map;
    }

    /**
     * needsArgument checks if an option string represents a user option that requires
     * an argument to be used correctly.
     * @param opt - the string of the user option.
     * @return true if the option is in the list of options that requires an argument, false otherwise.
     */
    @SuppressWarnings("empty-statement")
    private static boolean needsArgument(String opt)
    {
        opt = opt.toLowerCase();
        int i = 0;
        for (i = 0; i < optionsWithArgs.length && optionsWithArgs[i].compareTo(opt) != 0; i++);

        if (i >= optionsWithArgs.length)
        {
            return false;
        }

        return true;
    }
}
