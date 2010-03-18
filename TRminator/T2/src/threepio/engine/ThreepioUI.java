/*
 * File: ThreepioUI.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.engine;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import threepio.documenter.XDocumenter;

/**
 * ThreepioUI holds some commonly useful CLI methods.
 * @author jhoule
 */
public abstract class ThreepioUI
{

    public abstract void fail(String reason);

    public abstract void fail(String reason, Exception ex);

    /**
     * fail is a method for quitting unexpectedly, and reporting a reason to the user.
     * @param reason - the reason to give to the user.
     */
    public static void cli_fail(String reason)
    {
        System.err.println("ERROR: " + reason + " \nnow quitting.");

        System.exit(1);
    }

    /**
     * fail is a method for quitting unexpectedly, and reporting a reason to the user.
     * this fail accepts an exception as a reason for failure, and dispalys that fact to the user.
     * @param reason - the reason to give to the user.
     * @param ex - the exception that caused the failure.
     */
    public static void cli_fail(String reason, Exception ex)
    {
        System.err.println("ERROR: " + reason);
        ex.printStackTrace(System.err);
        System.err.println(" \nnow quitting.");

        System.exit(1);
    }

//    /**
//     * getIn returns a File for the input file chosen by the user.
//     * the program will exit if the path is incorrect, or the file is not readable.
//     * @param pathIn - the path to the real file.
//     * @return a File for the input.
//     */
//    protected File getIn(String pathIn)
//    {
//        // make File object for input
//        File fIn = null;
//
//        try
//        {
//            fIn = FileIntake.resolveFile(new File(pathIn), true);
//        } catch (Exception ex)
//        {
//            fail(ex.getMessage(), ex);
//        }
//
//        if (fIn == null)
//        {
//            fail("Input file " + pathIn + " does not exist");
//        }
//
//        if (!fIn.isFile())
//        {
//            fail("The input file " + pathIn + " is a directory.");
//        }
//
//        if (!fIn.canRead())
//        {
//            fail("Input file " + pathIn + " is not readable. Check to see if it is open.");
//        }
//
//        return fIn;
//    }
    /**
     * getModel returns a string for the model's name, within a BBF document.
     * if there are multiple models, the user is prompted to choose one or exit.
     * @param fIn - the input file to scour for models.
     * @return the name of the model found or chosen
     * @throws Exception when the XDocumenter has a problem getting model names.
     * @see XDocumenter#getMainModelNames(java.io.File) 
     */
    public String getModel(File fIn) throws Exception
    {
        // instance variables
        XDocumenter doccer = new XDocumenter();
        ArrayList<String> models;
        String fName;

        // use the XDocumenter to get the names of top-level models in the file.
        models = doccer.getMainModelNames(fIn);

        fName = fIn.getName();

        switch (models.size())
        {
            case 0:
            {
                // no models found.
                throw new Exception(fName + " doesn't contain any top-level models.");
            }

            case 1:
            {
                // there's only one model. return it.
                return models.get(0);
            }

            default:
            {
                // need to prompt user for which model.
                return promptForModel(fName, models);
            }
        }
    }

    /**
     * getOut returns a File for the output file chosen by the user.
     * an existent file at given path will get deleted in the process.
     * @param pathOut - the path for the output file, as provided by the user.
     * @return a File for putting the output into.
     * @throws IOException when the file management experiences an issue.
     */
    public File getOut(String pathOut) throws IOException
    {
        // make a file for output.
        File fOut = new File(pathOut);

        if (fOut.isDirectory())
        {
            fail("The output file is a directory!");
        }

        if (fOut.getParentFile() == null)
        {
            fOut = new File("." + File.separatorChar + fOut.getName());
        }

        // delete any file that exists there.
        if (fOut.exists())
        {
            System.out.println("INFO: deleting old file at " + fOut.getPath());
            fOut.delete();
        }

        // make a new file here.
        fOut.createNewFile();

        return fOut;
    }

    public abstract String promptForModel(String fileName, ArrayList<String> models);

    public abstract boolean init();
//     /**
//     * makeOptMap parses a String array into a HashMap.
//     * If an option requires an argument, the argument is the value to a key with that option.
//     * if the option does not require an argument, the key gets put on the map, with "true" as it's value.
//     * these "true" values are not currently in use.
//     *
//     * Options MUST start with a '-' character.
//     * Consequentially, arguments to options MUST NEVER start with a '-' character.
//     *
//     * @param opts - an arary of strings that represents the user's options.
//     * @return a HashMap of the user's selections.
//     * @throws Exception when an error in user input is found.
//     */
//    public HashMap<String, String> makeOptMap(String[] opts) throws Exception
//    {
//        HashMap<String, String> map = new HashMap<String, String>();
//        String key, val;
//        int sz = opts.length, difference;
//
//        for (int i = 0; i < sz; i++)
//        {
//            difference = sz - i;
//            key = opts[i].toLowerCase();
//
//            if (!key.startsWith("-"))
//            {
//                // all options should start with the dash.
//                throw new Exception("invalid option: " + key);
//            }
//
//            if (needsArgument(key))
//            {
//                if (difference < 2)
//                {
//                    // this option cannot be used without a following argument.
//                    throw new Exception("no arugment for option" + key);
//                }
//
//                // make lower case.
//                val = opts[++i].toLowerCase();
//
//                if (val.startsWith("-"))
//                {
//                    // it appears that another option is in the place of an argument for a previous option.
//                    throw new Exception("no arugment for option" + key);
//                }
//
//                map.put(key, val);
//            } else
//            {
//                // this option doesn't need an argument.
//                // it's presence as a key on the map will be used in the program,
//                // not it's value, but we put on a value of "true" just in case.
//                map.put(key, "true");
//
//            }
//        }
//
//        return map;
//    }
    /**
     * needsArgument checks if an option string represents a user option that requires
     * an argument to be used correctly.
     * @param opt - the string of the user option.
     * @return true if the option is in the list of options that requires an argument, false otherwise.
     */
}
