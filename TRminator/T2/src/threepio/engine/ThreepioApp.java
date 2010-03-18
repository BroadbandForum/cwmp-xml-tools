/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package threepio.engine;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Scanner;
import threepio.container.HashList;
import threepio.documenter.XDocumenter;
import threepio.filehandling.FileIntake;

/**
 *
 * @author jhoule
 */
public abstract class ThreepioApp
{

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
     * @param owa - a hashmap where the keys are options and the arguments are an amount of args.
     * @return a HashMap of the user's selections.
     * @throws Exception when an error in user input is found.
     */
    public static HashList<String, String> makeOptMap(String[] opts, HashMap<String, Integer> owa) throws Exception
    {
        HashList<String, String> map = new HashList<String, String>();
        String key, val;
        int sz = opts.length, difference, numArgs;

        for (int i = 0; i < sz; i++)
        {
            difference = sz - i;
            key = opts[i].toLowerCase();

            if (!key.startsWith("-"))
            {
                // all options should start with the dash.
                throw new Exception("invalid option: " + key);
            }

            if (owa.containsKey(key))
            {
                numArgs = owa.get(key);

                if (difference < numArgs)
                {
                    // this option cannot be used without a following argument.
                    throw new Exception("not enough arugments for option" + key);
                }

                for (int j = 0; j < numArgs; j++)
                {
                    // make lower case.
                    val = opts[++i].toLowerCase();

                    if (val.startsWith("-"))
                    {
                        // it appears that another option is in the place of an argument for a previous option.
                        throw new Exception("not enough arguments for option" + key);
                    }

                    map.put(key, val);
                }

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
     * getIn returns a File for the input file chosen by the user.
     * the program will exit if the path is incorrect, or the file is not readable.
     * @param pathIn - the path to the real file.
     * @return a File for the input.
     */
    protected static File getIn(String pathIn) throws Exception
    {
        // make File object for input
        File fIn = null;

        fIn = FileIntake.resolveFile(new File(pathIn), true);

        if (fIn == null)
        {
            throw new Exception("Input file " + pathIn + " does not exist");
        }

        if (!fIn.isFile())
        {
            throw new Exception("The input file " + pathIn + " is a directory.");
        }

        if (!fIn.canRead())
        {
            throw new Exception("Input file " + pathIn + " is not readable. Check to see if it is open.");
        }

        return fIn;
    }
}
