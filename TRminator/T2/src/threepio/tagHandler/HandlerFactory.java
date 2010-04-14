/*
 * File: HandlerFactory.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tagHandler;

import java.util.HashMap;
import java.util.Map.Entry;
import threepio.documenter.XTag;
import java.util.logging.Level;
import java.util.logging.Logger;
import threepio.tabler.container.ColumnMap;

/**
 * HandlerFactory doles out Handlers to other classes.
 * @author jhoule
 */
public class HandlerFactory
{
    /**
     * IMPORTANT: add any required handler class to this array!
     * It's really not a bad idea to just have all TagHandler classes on this
     * list. That way, the parser will have a full library of handlers.
     */
    private Class[] handlers =
    {
        DescriptionHandler.class,
        SyntaxHandler.class,
        TitleHandler.class,
        NameHandler.class,
        DateHandler.class,
        HyperlinkHandler.class,
        OrganizationHandler.class,
        CategoryHandler.class
    };

    /**
     * a map of the handlers availalbe to the Factory.
     */
    private HashMap<String, TagHandler> handlerMap = new HashMap<String, TagHandler>();

    /**
     * no-argument constructor.
     * Sets up the Handler Map.
     */
    public HandlerFactory()
    {
        String type;
        TagHandler h;

        // go through the handlers, adding them to the map.
        for (int i = 0; i < handlers.length; i++)
        {
            try
            {
                h = (TagHandler) handlers[i].newInstance();
                type = h.getTypeHandled();
                handlerMap.put(type, h);

            } catch (InstantiationException ex)
            {
                Logger.getLogger(HandlerFactory.class.getName()).log(Level.SEVERE, "could not instantiate a handler", ex);
            } catch (IllegalAccessException ex)
            {
                Logger.getLogger(HandlerFactory.class.getName()).log(Level.SEVERE, "could not access the constructor of a handler", ex);
            }
        }
    }

    public HandlerFactory(ColumnMap toMake)
    {
        this();
        for (Entry<String, String> e: toMake)
        {
            handlerMap.put(e.getValue(), new GeneralTagHandler(e.getKey(), e.getValue()));
        }
    }

    /**
     * returns a handler that is made to handle the tag passed.
     * @param t - the tag
     * @return the handler
     * @throws Exception - when a handler cannot be found.
     * @see XTag
     */
    public TagHandler getHandler(XTag t) throws Exception
    {
        TagHandler h = (handlerMap.get(t.getType()));

        if (h == null)
        {
            throw new Exception("No handler for tag type " + t.getType());
        }

        return h;
    }

    /**
     * returns a handler that is made to handle the tag passed.
     * @param type - the tag type
     * @return the handler
     * @throws Exception - when a handler cannot be found.
     * @see XTag
     */
    public TagHandler getHandler(String type) throws Exception
    {
        TagHandler h = (handlerMap.get(type));

        if (h == null)
        {
            throw new Exception("No handler for tag type " + type);
        }

        return h;
    }
}
