/*
 * File: TRComponent.java
 * Project: Threepio
 * Author: Jeff Houle
 */

package threepio.tabler.container;

import java.util.HashMap;

/**
 * TRComponent is a class that defines a Component from a BBF document.
 * It is exclusively a container, with some constructors, getters, and setters.
 * @author jhoule
 */
public class TRComponent {

    String name;
    String description;
    HashMap<String, String> parameters;

    XTable table;

    /**
     * no-argument constructor.
     * sets up parameters.
     */
    public TRComponent()
    {
        parameters = new HashMap<String, String>();
        description = new String();
        name = new String();
    }

    /**
     * constructor that accepts a table.
     * sets this component's table to the specified table.
     * @param t - the table.
     */
    public TRComponent(XTable t)
    {
        this();
        table = t;
    }

    /**
     * constructor that accepts a table and a description String
     * @param t - the table
     * @param desc - the description string.
     */
    public TRComponent(XTable t, String desc)
    {
        this(t);
        description = desc;
    }

    /**
     * returns the descripition string
     * @return the description, as a string.
     */
    public String getDescription()
    {
        return description;
    }

    /**
     * sets the description string.
     * @param desc - the description string to set the internal string to.
     */
    public void setDescription(String desc)
    {
        description = desc;
    }

    /**
     * sets a parameter of the component.
     * @param key - key for the parameter.
     * @param val - value of the parameter.
     */
    public void setParam(String key, String val)
    {
        parameters.put(key, val);
    }

    /**
     * returns the map of parameters.
     * @return a HashMap of the parameters, with keys and values of strings.
     */
    public HashMap<String, String> getParams()
    {
        return parameters;
    }

    /**
     * returns the table inside the component.
     * @return the table.
     */
    public XTable getTable()
    {
        return table;
    }

    /**
     * puts all parameters in HashMap passed into the internal hashmap.
     * @param map - the map to import parameters from.
     */
    public void importParams(HashMap<String, String> map)
    {
        parameters.putAll(map);
        this.name = parameters.get("ref");
    }

    /**
     * returns the name of the component.
     * @return the component name.
     */
    @Override
    public String toString()
    {
        return name;
    }

}
