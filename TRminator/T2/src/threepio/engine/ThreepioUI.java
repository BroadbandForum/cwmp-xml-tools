/*
 * File: ThreepioUI.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.engine;

import java.io.File;
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

    public void failOut(String reason)
    {
        fail(reason);
        System.exit (-1);
    }

    public void failOut(String reason, Exception ex)
    {
        fail(reason, ex);
        System.exit(-1);
    }

    /**
     * fail is a method for quitting unexpectedly, and reporting a reason to the user.
     * @param reason - the reason to give to the user.
     */
    public static void cli_failOut(String reason)
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

   

    public abstract String promptForModel(String fileName, ArrayList<String> models);

    public abstract void init() throws Exception;

}
