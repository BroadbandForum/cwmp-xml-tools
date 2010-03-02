/*
 * File: MotrCLI.java
 * Project: moTR
 * Author: Jeff Houle
 */
package motr;

import java.io.File;
import java.io.IOException;
import java.util.HashMap;
import threepio.engine.CommonCLI;
import threepio.engine.Engine;
import threepio.engine.UITools;
import threepio.filehandling.FileIntake;
import threepio.tabler.container.ColumnMap;
import threepio.tabler.container.ModelTable;

/**
 * MotrCLI is a command-line interface for moTR: the motive TR converter.
 * Command-line arguments are:
 *  -i <input_path>
 *  -o <output_path>
 *  -f <wrapper file>
 * @see Engine#wrapStringWithFile(java.lang.String, java.io.File, java.io.File, java.lang.String)
 * @author jhoule
 */
public class MotrCLI extends CommonCLI
{

    /**
     * options with arguments
     */
    private final String[] oWA =
    {
        "-i", "-o", "-f"
    };

    MotrCLI(String name)
    {
        super (name);
    }

    private MotrCLI()
    {
        super ();
    }

    /**
     * The options that have arguments for moTR's cli
     * @return an array of the options that have arguments.
     */
    @Override
    public String[] optionsWithArgs()
    {
        return oWA;
    }

    /**
     * the main function of MotrCLI is to use the command-line arguments
     * to produce a Motive Device Model XML file from a BBF TR
     * @param args - command line arguments
     */
    public static void main(String args[])
    {
        // instance variables.
        MotrCLI cli = new MotrCLI();
        MotrEngine motr = new MotrEngine();
        String pathIn = null, pathOut = null, modelName = null, depends = new String();
        HashMap<String, String> userOpts = null;
        ColumnMap cols = new ColumnMap();
        File fIn = null, fOut = null, wrapper = null;
        ModelTable table;
        int typeCol;

        // set up the default columns.
        UITools.setupCols(cols);
        System.out.println(MotrApp.appVersion + " is starting...\n");

        try
        {
            userOpts = cli.makeOptMap(args);
        } catch (Exception ex)
        {
            fail("could not map user options:\n\t" + ex.getMessage(), ex);
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

            if (userOpts.containsKey("-f"))
            {
                wrapper = new File(userOpts.get("-f"));
                wrapper = FileIntake.resolveFile(wrapper);
            }


        } catch (Exception ex)
        {
            fail("could not parse arguments into essential variables", ex);
        }

        // create File object for input file.
        fIn = getIn(pathIn);

        // create File object for output file.
        try
        {
            fOut = getOut(pathOut);

        } catch (IOException ex)
        {
            fail("could not initailize all required files", ex);
        }

        // get the model name for the resulting table.
        try
        {
            modelName = getModel(fIn);

            if (modelName == null)
            {
                fail("no model name selected for input");
            }

        } catch (Exception ex)
        {
            fail("could not obtain a valid model name", ex);
        }

        // check to make sure no required files are missing.
        try
        {
            depends = motr.getMissingDepends(pathIn, modelName);

        } catch (Exception ex)
        {
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

            table = motr.docToModelTable(cols, modelName, pathIn, "Object");

            if (wrapper == null)
            {
                motr.printModelTable(table, fOut);
            } else
            {
                motr.printWrappedTable(table, fOut, wrapper);
            }


        } catch (Exception ex)
        {
            fail("Could not make table:\n\t" + ex.getMessage(), ex);

        }

    }
}
