/*
 * File: TRminatorGUI.java
 * Project: TRminator
 * Author: Jeff Houle
 *
 */

package trminator;

import java.util.ArrayList;
import java.util.logging.Level;
import java.util.logging.Logger;
import threepio.tabler.container.ColumnMap;

/**
 * TRminatorGUI drives a TRminatorGUIPanel and interacts with a TRminatorAPP
 * to complete user-defined tasks using TRminator methods.
 * @author jhoule
 * @see TRminatorGUIPanel
 * @see TRminatorApp
 */
public class TRminatorGUI extends TRminatorUI
{

    /**
     * the Panel to interact with the user.
     */
    private TRminatorGUIPanel panel;

    /**
     * Default constructor.
     * @param app - the application the GUI runs on top of.
     */
    public TRminatorGUI(TRminatorApp app)
    {
        super(app);

        panel = new TRminatorGUIPanel(this);
    }

    /**
     * exposes the makeTable() functionality of the underlying TRminatorApp.
     * @see TRminatorApp#makeTable() 
     */
    protected void makeTable()
    {
        myApp.makeTable();
    }

    /**
     * Loads the user-selected files and checks for existence and depenencies.
     * @return true iff the files are loaded and seem to be okay, false otherwise.
     */
    protected boolean loadFiles()
    {
        boolean temp;

        try
        {
            updateVariables();
        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorGUI.class.getName()).log(Level.SEVERE, null, ex);
            fail("could not update variables", ex);
        }
        myApp.collectFiles();
        temp = myApp.doChecks();
        updateFields();

        panel.loaded = true;

        return temp;
    }

    /**
     * pops up the error defined by the TRminatorApp.
     * @param reason - the reason for the error.
     */
    @Override
    public void fail(String reason)
    {
        panel.popupError(reason);
    }

    /**
     * pops up the error defined by the TRminatorApp.
     * @param reason - the reason for the error.
     * @param ex - the Exception associated with the error.
     */
    @Override
    public void fail(String reason, Exception ex)
    {
        StringBuffer buff = new StringBuffer();

        buff.append(reason);
        buff.append(":\n");
        buff.append(ex.getMessage());

        panel.popupError(buff.toString(), ex.getClass().getName());
    }

    @Override
    protected void updateVariables()
    {
        if (panel != null)
        {
            myApp.pathOut = panel.getOutputPath();
            myApp.pathIn = panel.getInputPathOne();
            myApp.pathTwo = panel.getInputPathTwo();
            myApp.diff = panel.getDiffing();
            myApp.looks = panel.getLooks();
            myApp.prof = panel.getDoProfiles();
            myApp.containerName = panel.getContainerName();
            myApp.cols = panel.cols;
        }
    }

    /**
     * updates the fields of the TRminatorGUIPanel to reflect the TRminatorApp.
     * @throws Exception when there is a conflict in setting values.
     */
    @Override
    public void init() throws Exception
    {
        updateFields();
    }

    @Override
    public String promptForModel(String fileName, ArrayList<String> models)
    {
        return panel.chooseFromList("choose a model from " + fileName, 
                "Please click the name of the desired model:" , models);
    }

    /**
     * Makes the Panel show, so the user can begin interacting with it.
     */
    public void run()
    {
        panel.setVisible(true);
    }

    @Override
    protected void updateStatusMsg(String msg)
    {
        panel.setStatus(msg);
    }

    /**
     * returns the map of columns that the program and/or user has created.
     * @return the map of columns.
     */
    protected ColumnMap getCols()
    {
        return myApp.cols;
    }

    /**
     * Sets the underlying application's output path instance variable.
     * @param path - the string to set the path to.
     * @see TRminatorApp#pathOut
     */
    protected void setOutputPath(String path)
    {
        myApp.pathOut = path;
    }

    /**
     * Sets the underlying application's first input path instance variable.
     * @param path - the string to set the path to.
     * @see TRminatorApp#pathIn
     */
    protected void setInputPathOne(String path)
    {
        myApp.pathIn = path;
    }

    /**
     * Sets the underlying application's second input path instance variable.
     * @param path - the string to set the path to.
     * @see TRminatorApp#pathTwo
     */
    protected void setInputPathTwo(String path)
    {
        myApp.pathTwo = path;
    }

    /**
     * Checks to make sure options and modes are allowed to be used at the same time,
     * Then sets the mode based on the user options.
     * @return true iff the mode coudl be set or changed, false otherwise.
     */
    protected boolean changeModes()
    {
        if (myApp.genericTable)
        {
            if (myApp.diffingTwo)
            {
                fail("cannot use \"diffingTwo\" with \"genericTable\" ");
                return false;
            }

            try
            {
                return panel.setMode(2);

            } catch (Exception ex)
            {
                Logger.getLogger(TRminatorGUI.class.getName()).log(Level.SEVERE, null, ex);
                fail("GUI does not know \"genericTable\" mode", ex);
                return false;
            }
        }

        if (myApp.diffingTwo)
        {
            if (myApp.genericTable)
            {
                fail("cannot use \"diffingTwo\" with \"genericTable\" ");
                return false;
            }

            try
            {
                return panel.setMode(1);
            } catch (Exception ex)
            {
                Logger.getLogger(TRminatorGUI.class.getName()).log(Level.SEVERE, null, ex);
                fail("GUI does not know \"diffingTwo\" mode", ex);
                return false;
            }
        }

        try
        {
            return panel.setMode(0);
        } catch (Exception ex)
        {
            Logger.getLogger(TRminatorGUI.class.getName()).log(Level.SEVERE, null, ex);
            fail("GUI does not know default mode", ex);
            return false;
        }
    }

    @Override
    protected void updateFields()
    {

        if (changeModes())
        {
            updateStatusMsg("mode changed");
        }

        panel.cols = myApp.cols;
        panel.setOutputPath(myApp.pathOut);
        panel.setInputPathOne(myApp.pathIn);
        panel.setInputPathTwo(myApp.pathTwo);
        panel.setDiffing(myApp.diff);
        panel.setLooks(myApp.looks);
        panel.setDoProfiles(myApp.prof);
        panel.setModel(myApp.modelName);
        panel.setModelTwo(myApp.modelTwo);
        panel.setContainerName(myApp.containerName);


    }
}
