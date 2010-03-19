/*
 * File: TRminatorCLI.java
 * Project: TRminator
 * Author: Jeff Houle
 */
package trminator;

import java.util.ArrayList;
import java.util.Scanner;

/**
 * TRminatorCLI defines a command-line interface for TRminator.
 * @author jhoule
 */
public class TRminatorCLI extends TRminatorUI
{

    public TRminatorCLI(TRminatorApp app)
    {
        super(app);
    }

    /**
     * The main function of TRminatorCLI is to provide a command-line interface
     * for creating HTML tables, in files, from XML Data Models, like those made by
     * the BBF.
     */
    public void run()
    {  
        System.out.println(TRminatorApp.appVersion + " is starting...\n");
        
    }

    @Override
    protected void updateStatus()
    {
        throw new UnsupportedOperationException("Not supported yet.");
    }

    @Override
    public void fail(String reason)
    {
        throw new UnsupportedOperationException("Not supported yet.");
    }

    @Override
    public void fail(String reason, Exception ex)
    {
        throw new UnsupportedOperationException("Not supported yet.");
    }

    @Override
    public boolean init()
    {
        throw new UnsupportedOperationException("Not supported yet.");
    }

    @Override
    public String promptForModel(String fileName, ArrayList<String> models)
    {
        Scanner scan;
        String userInput;
        Integer choice;

        // need to prompt user for which model.
        Boolean done = false;

        while (!done)
        {
            System.out.println("Multiple Models exist in " + fileName
                    + "\nPlease Choose via number, or exit with 0.");

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

// never actually gets here (the list cant' have a size <0).
        return null;

    }
}
