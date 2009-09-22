/*
 * File: BBFEnum.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler;

import threepio.documenter.XTag;

/**
 * BBFEnum is a class representing enumerations from BBF XML code.
 * @author jhoule
 */
public class BBFEnum
{

    private String value, description, access;

    /**
     * full constructor
     * @param v - value of enumeration
     * @param d - description of enumeration
     * @param a - access attribute of enumeration.
     */
    public BBFEnum(String v, String d, String a)
    {
        value = v;

        if (d == null)
        {
            description = "";
        } else
        {
            description = d;
        }

        if (a == null)
        {
            access = "";
        } else
        {
            access = a;
        }

    }

    /**
     * Value-only constructor
     * @param v - value of enumeration
     */
    public BBFEnum(String v)
    {
        this(v, new String(), new String());
    }

    /**
     * Value and description constructor
     * @param v - value of enumeration
     * @param d - description of enumeration
     */
    public BBFEnum(String v, String d)
    {
        this(v, d, new String());
    }

    public BBFEnum(XTag t)
    {
        this(t.getParams().get("value"), t.getParams().get("description"), t.getParams().get("access"));
    }

    /**
     * returns the value of the enumeration.
     * @return the value.
     */
    public String getValue()
    {
        return value;
    }

    /**
     * returns the description of the enumeration.
     * @return the description.
     */
    public String getDescription()
    {
        return description;
    }

    /**
     * returns the access attribute of the enumeration.
     * @return the access attribute
     */
    public String getAccess()
    {
        return access;
    }
}
