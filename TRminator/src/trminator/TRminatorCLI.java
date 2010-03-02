/*
 * File: TRminatorCLI.java
 * Project: TRminator
 * Author: Jeff Houle
 */
package trminator;

import threepio.engine.UITools;
import threepio.tabler.TablePostProcessor;
import java.io.File;
import java.io.IOException;
import java.util.HashMap;
import java.util.logging.*;
import threepio.engine.CommonCLI;
import threepio.engine.ThreepioEngine;
import threepio.filehandling.FileIntake;
import threepio.tabler.container.ColumnMap;
import threepio.tabler.container.ModelTable;

/**
 * TRminatorCLI defines a command-line interface for TRminator.
 * @author jhoule
 */
public class TRminatorCLI extends CommonCLI
{
    // the option strings that require an argument.

    final String[] oWA =
    {
        "-i", "-o", "-ii"
    };

    @Override
    public String[] optionsWithArgs()
    {
        return oWA;
    }

    /**
     * The main function of TRminatorCLI is to provide a command-line interface
     * for creating HTML tables, in files, from XML Data Models, like those made by
     * the BBF.
     * @param args - command-line arguments.
     */
    public static void main(String args[])
    {
        // instance variables.
        TRminatorCLI cli = new TRminatorCLI();
        ThreepioEngine seeThree = new ThreepioEngine();
        Boolean diff = Boolean.TRUE, diffingTwo = Boolean.FALSE, prof = Boolean.FALSE, looks = Boolean.FALSE;
        String pathIn = null, pathTwo = null, pathOut = null, modelName = null, modelTwo = null, depends = new String();
        HashMap<String, String> userOpts = null;
        ColumnMap cols = new ColumnMap();
        File fIn = null, fTwo = null, fOut = null;
        ModelTable table;
        TablePostProcessor processor = new TablePostProcessor();
        int typeCol;

        // set up the default columns.
        UITools.setupCols(cols);
        System.out.println(TRminatorApp.appVersion + " is starting...\n");

        try
        {
            userOpts = cli.makeOptMap(args);
        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "cannot continue without options", ex);
            fail("could not map user options", ex);
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
            fail("could not parse options into essential variables", ex);
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
            fail("could not initailize all required files", ex);
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
            fail("could not obtain a valid model name", ex);
        }

        // check to make sure no required files are missing.
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
            fail("missing some files the model is dependent on", ex);
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
                table = seeThree.diffTwoTables(cols, modelName, pathIn, modelTwo, pathTwo, fOut, "Object");
            } else
            {
                table = seeThree.docToModelTable(cols, modelName, pathIn, "Object");
            }
            processor.deMarkupTable(table, new File(fOut.getParent() + FileIntake.fileSep + "post.err"), typeCol);
            seeThree.printModelTable(table, fOut, diff, prof, looks);

        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorCLI.class.getName()).log(Level.SEVERE, "Could not make table", ex);
            fail("Could not make table:\n\t" + ex.getMessage(), ex);
        }
    }


   
}
