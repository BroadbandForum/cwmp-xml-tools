/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package trminator;

/**
 *
 * @author jhoule
 */
public class TRminatorGUI extends TRminatorUI {

    private TRminatorGUIPanel gui;

    public TRminatorGUI(TRminatorApp app)
    {
        super(app);

        gui = new TRminatorGUIPanel();
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
    protected void updateStatus()
    {
        throw new UnsupportedOperationException("Not supported yet.");
    }

    @Override
    public boolean init()
    {
        throw new UnsupportedOperationException("Not supported yet.");
    }

}
