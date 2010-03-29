/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package trminator;

import java.util.ArrayList;
import java.util.logging.Level;
import java.util.logging.Logger;
import threepio.tabler.container.ColumnMap;

/**
 *
 * @author jhoule
 */
public class TRminatorGUI extends TRminatorUI
{

    private TRminatorGUIPanel panel;

    public TRminatorGUI(TRminatorApp app)
    {
        super(app);

        panel = new TRminatorGUIPanel(this);
    }

    protected void makeTable()
    {
        myApp.makeTable();
    }

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

        return temp;
    }

    @Override
    public void fail(String reason)
    {
        panel.popupError(reason);
    }

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

    @Override
    public void init() throws Exception
    {
        updateFields();
    }

    @Override
    public String promptForModel(String fileName, ArrayList<String> models)
    {
        throw new UnsupportedOperationException("Not supported yet.");
    }

    public void run()
    {
        panel.setVisible(true);
    }

    @Override
    protected void updateStatus(String msg)
    {
        panel.setStatus(msg);
    }

    protected ColumnMap getCols()
    {
        return myApp.cols;
    }

    protected void setOutputPath(String path)
    {
        myApp.pathOut = path;
    }

    protected void setInputPathOne(String path)
    {
        myApp.pathIn = path;
    }

    protected void setInputPathTwo(String path)
    {
        myApp.pathTwo = path;
    }

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
            updateStatus("mode changed");
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
