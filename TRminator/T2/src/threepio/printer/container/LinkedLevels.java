/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package threepio.printer.container;

import java.util.ArrayList;
import threepio.helper.XHTMLHelper;
import threepio.tabler.Path;

/**
 *
 * @param <X> - the type of object that will be in the level
 * @author jhoule
 */
public class LinkedLevels<X>
{

    /**
     * the name of the root StringLevel
     */
    public final static String rootName = Path.rootName;
    private Level<X> current;

    /**
     * default constructor.
     * makes the root StringLevel and names it, setting it as the current StringLevel.
     */
    public LinkedLevels()
    {
        current = new Level<X>(0);
        current.id = rootName;
    }

    /**
     * goes "in" a level, creating a new level that is an offshoot of the current one.
     * this new level will have a depth that is +1 of the current depth.
     * this new level will be a "child" of the current level.
     */
    public void in()
    {
        Level<X> l;
        l = new Level<X>(getDepth() + 1);

        current.addChild(l);

        current = l;

    }

    /**
     * returns the depth of the curent StringLevel.
     * @return the current StringLevel's depth.
     */
    public int getDepth()
    {
        return current.depth;
    }

    /**
     * goes "out" a level.
     * if this is the root object, an exception is thrown.
     * otherwise, sets the current StringLevel to the "parent" StringLevel of the current StringLevel.
     * @throws IllegalStateException - when the current StringLevel is the root.
     */
    public void out()
    {

        if (current.prev == null)
        {
            throw new IllegalStateException("already at lowest level");
        }

        current = current.prev;
    }

    /**
     * Adds an object to the Level.
     * @param x - the thing to add.
     */
    public void add(X x)
    {

        current.add(x);
    }

    /**
     * sets the label for the current level.
     * @param s - the label to set.
     */
    public void setLabel(String s)
    {
        current.label = s;
    }

    /**
     * sets the ID for the current level.
     * @param id - the ID to set for the level.
     */
    public void setID(String id)
    {
        current.id = id;
    }

    /**
     * returns the ID of the current level.
     * @return the ID of the current level
     */
    public String getID()
    {

        return current.id;
    }

    /**
     * Sets the trailing text for the current level.
     * @param s - the trailing text for the level.
     */
    public void setTrailer(String s)
    {
        current.trailer = s;
    }

    /**
     * returns the string representation of the LinkedLevels.
     * This is done recursively via the toString() of the root level.
     * @return the structure, in string form.
     */
    @Override
    public String toString()
    {
        return root().toString();
    }

    /**
     * returns the root Level of this LinkedLevels object.
     * Done by following links back from current level.
     * Does not change the pointer for the current level.
     * @return the root level.
     */
    private Level<X> root()
    {
        Level<X> l = current;

        while (l.prev != null)
        {
            l = l.prev;
        }

        return l;
    }

     /**
     * returns the root Level of this LinkedLevels object.
     * Done by following links back from current level.
     * WARNING: changes the current pointer to the root level.
     * @return the root level.
     */
    private Level returnToTop()
    {
        while (current.prev != null)
        {
            current = current.prev;
        }

        return current;
    }

    /**
     * Level is a level in the LinkedLevels structure.
     * @param <X> - the kind of item to be stored in the Level.
     */
    private class Level<X> extends ArrayList<X>
    {
        private Level<X> prev;
        private int depth;
        private ArrayList<Level> children;
        private String label, trailer, id;

        public Level()
        {
            depth = 0;
            children = new ArrayList<Level>();
            prev = null;

            label = "";
            trailer = "";
        }

        public Level(int d)
        {
            this();
            depth = d;

        }

        public void setID(String anID)
        {
            this.id = anID;
        }

        public void addChild(Level<X> l)
        {
            children.add(l);
            l.depth = this.depth + 1;
            l.prev = this;
        }

        @Override
        public String toString()
        {
            String tabString, otherTabs;
            StringBuffer buff = new StringBuffer();

            tabString = XHTMLHelper.tabber(this.depth);
            otherTabs = XHTMLHelper.tabber((this.depth + 1));
            buff.append(tabString);
            buff.append(this.label);
            buff.append("\n");

            for (X s : this)
            {
                buff.append(otherTabs);
                buff.append(s);
                buff.append("\n");
            }

            for (Level l : this.children)
            {
                buff.append(l.toString());
            }

            buff.append(tabString);
            buff.append(this.trailer);
            buff.append("\n");

            return buff.toString();
        }
    }
}
