/*
 * File: TRminatorApp.java
 * Project: TRminator
 * Author: Jeff Houle
 */
package trminator;

import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * TRminatorApp is the main application of the TRminator.
 * It provides the user with access to both the graphical and command-line interfaces,
 * and is where the command-line interface is defined.
 * @author jhoule
 */
public class TRminatorApp
{
    public static final String appVersion = "TRminator RC3 (100909)";
    private static final  String strUseGui = "-gui", strUseCli = "-cli";
    private static final String[] modes =
    {
        strUseGui, strUseCli
    };

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
        String[] newArgs;
        int mode = -1;

        switch (args.length)
        {
            case 0:
            {
                // no arguments, so open up a GUI.
                TRminatorGUI.main(appVersion, null);
                break;
            }

            default:
            {
                mode = getMode(args[0]);
                newArgs = new String[args.length - 1];

                for (int i = 1; i < args.length; i++)
                {
                    newArgs[i - 1] = args[i];
                }

                switch (mode)
                {
                    case 0:
                    {
                        // using the gui, pass arguments on, except first.
                        TRminatorGUI.main(appVersion, newArgs);
                        break;
                    }

                    case 1:
                    {

                        if (newArgs.length < 1)
                        {
                            System.err.println("ERROR: No arguments found for CLI mode!");
                        } else
                        {
                            try
                            {
                                TRminatorCLI.main(appVersion, newArgs);

                            } catch (Exception ex)
                            {
                                Logger.getLogger(TRminatorApp.class.getName()).log(Level.SEVERE, "the CLI exited unexpectedly.", ex);
                                System.err.println("ERROR: CLI exited unhappily");
                            }
                        }
                        break;
                    }
                    default:
                    {
                        System.err.println("ERROR: unknown mode (Did you forget to specify it in the first argument?)\nQuitting");
                    }
                }
            }
        }
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
}
