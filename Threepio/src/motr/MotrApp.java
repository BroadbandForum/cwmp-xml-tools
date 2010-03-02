/*
 * File: MotrApp.java
 * Project: moTR
 * Author: Jeff Houle
 */
package motr;

/**
 * MotrApp is the main application for moTR: the motive TR converter.
 * @author jhoule
 */
public class MotrApp
{

    public static final String appVersion = "moTR 2 (291009)";

    /**
     * main kicks off the CLI for moTR.
     * @param args - arguments for the CLI.
     */
    public static void main(String args[])
    {
        MotrCLI.main(args);
    }
}
