/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2013 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

package ti.modules.titanium.ui.widget.listview;


import java.util.ArrayList;
import java.util.HashMap;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollModule;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.kroll.common.AsyncResult;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.kroll.common.TiMessenger;
import org.appcelerator.titanium.TiApplication;
import org.appcelerator.titanium.TiC;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.view.TiUIView;

import ti.modules.titanium.ui.UIModule;
import android.app.Activity;
import android.os.Handler;
import android.os.Message;

@Kroll.proxy(creatableInModule = UIModule.class, propertyAccessors = {
	TiC.PROPERTY_HEADER_TITLE,
	TiC.PROPERTY_FOOTER_TITLE,
	TiC.PROPERTY_TEMPLATES,
	TiC.PROPERTY_DEFAULT_ITEM_TEMPLATE,
	TiC.PROPERTY_SHOW_VERTICAL_SCROLL_INDICATOR,
	TiC.PROPERTY_SECTIONS,
	TiC.PROPERTY_SEPARATOR_COLOR,
	TiC.PROPERTY_SEARCH_TEXT,
	TiC.PROPERTY_SEARCH_VIEW,
	TiC.PROPERTY_CASE_INSENSITIVE_SEARCH
})
public class ListViewProxy extends TiViewProxy {

	private static final String TAG = "ListViewProxy";
	
	private static final int MSG_FIRST_ID = TiViewProxy.MSG_LAST_ID + 1;

	private static final int MSG_SECTION_COUNT = MSG_FIRST_ID + 399;
	private static final int MSG_SCROLL_TO_ITEM = MSG_FIRST_ID + 400;
	private static final int MSG_APPEND_SECTION = MSG_FIRST_ID + 401;
	private static final int MSG_INSERT_SECTION_AT = MSG_FIRST_ID + 402;
	private static final int MSG_DELETE_SECTION_AT = MSG_FIRST_ID + 403;
	private static final int MSG_REPLACE_SECTION_AT = MSG_FIRST_ID + 404;
	private static final int MSG_SCROLL_TO_TOP = MSG_FIRST_ID + 405;
	private static final int MSG_SCROLL_TO_BOTTOM = MSG_FIRST_ID + 406;
	private static final int MSG_CLOSE_PULL_VIEW = MSG_FIRST_ID + 407;
	private static final int MSG_SHOW_PULL_VIEW = MSG_FIRST_ID + 408;


	//indicate if user attempts to add/modify/delete sections before TiListView is created 
	private boolean preload = false;
	private ArrayList<ListSectionProxy> preloadSections;
	private HashMap<String, Integer> preloadMarker;
	
	public ListViewProxy() {
		super();
	}

	public TiUIView createView(Activity activity) {
		return new TiListView(this, activity);
	}
	
	public void handleCreationArgs(KrollModule createdInModule, Object[] args) {
		preloadSections = new ArrayList<ListSectionProxy>();
		defaultValues.put(TiC.PROPERTY_DEFAULT_ITEM_TEMPLATE, UIModule.LIST_ITEM_TEMPLATE_DEFAULT);
		defaultValues.put(TiC.PROPERTY_CASE_INSENSITIVE_SEARCH, true);
		super.handleCreationArgs(createdInModule, args);
		
	}

	@Override
	public void handleCreationDict(KrollDict options) {
		super.handleCreationDict(options);
		//Adding sections to preload sections, so we can handle appendSections/insertSection
		//accordingly if user call these before TiListView is instantiated.
		if (options.containsKey(TiC.PROPERTY_SECTIONS)) {
			Object obj = options.get(TiC.PROPERTY_SECTIONS);
			if (obj instanceof Object[]) {
				addPreloadSections((Object[]) obj, -1, true);
			}
		}
	}
	
	public void clearPreloadSections() {
		if (preloadSections != null) {
			preloadSections.clear();
		}
	}
	
	public ArrayList<ListSectionProxy> getPreloadSections() {
		return preloadSections;
	}
	
	public boolean isPreload() {
		return preload;
	}
	
	public HashMap<String, Integer> getPreloadMarker()
	{
		return preloadMarker;
	}

	private void addPreloadSections(Object secs, int index, boolean arrayOnly) {
		if (secs instanceof Object[]) {
			Object[] sections = (Object[]) secs;
			for (int i = 0; i < sections.length; i++) {
				Object section = sections[i];
				addPreloadSection(section, -1);
			}
		} else if (!arrayOnly) {
			addPreloadSection(secs, -1);
		}
	}
	
	private void addPreloadSection(Object section, int index) {
		if (section instanceof ListSectionProxy) {
			if (index == -1) {
				preloadSections.add((ListSectionProxy) section);
			} else {
				preloadSections.add(index, (ListSectionProxy) section);
			}
		}
	}
	
	@Kroll.method @Kroll.getProperty
	public int getSectionCount() {
		if (TiApplication.isUIThread()) {
			return handleSectionCount();
		} else {
			return (Integer) TiMessenger.sendBlockingMainMessage(getMainHandler().obtainMessage(MSG_SECTION_COUNT));
		}
	}
	
	@Kroll.method
	public ListSectionProxy getSectionAt(int sectionIndex) {
		TiListView listView = (TiListView)peekView();
		if (listView != null) {
			return listView.getSectionAt(sectionIndex);
		} else {
			if (sectionIndex < 0 || sectionIndex >= preloadSections.size()) {
				Log.e(TAG, "getItem Invalid section index");
				return null;
			}
			
			return preloadSections.get(sectionIndex);
		}
	}
	
	public int handleSectionCount () {
		TiUIView listView = peekView();
		if (listView != null) {
			return ((TiListView) listView).getSectionCount();
		}
		return 0;
	}

	@Kroll.method
	public void scrollToItem(int sectionIndex, int itemIndex, @Kroll.argument(optional = true) KrollDict options) {
		boolean animated = TiConvert.toBoolean(options, TiC.PROPERTY_ANIMATED, true);
		if (TiApplication.isUIThread()) {
			handleScrollToItem(sectionIndex, itemIndex, animated);
		} else {
			KrollDict d = new KrollDict();
			d.put("itemIndex", itemIndex);
			d.put("sectionIndex", sectionIndex);
			d.put("animated", animated);
			TiMessenger.sendBlockingMainMessage(getMainHandler().obtainMessage(MSG_SCROLL_TO_ITEM), d);
		}
	}
	
	@Kroll.method
	public TiViewProxy getChildByBindId(int sectionIndex, int itemIndex, String bindId) {
		TiUIView listView = peekView();
		if (listView != null) {
			return ((TiListView) listView).getChildByBindId(sectionIndex, itemIndex, bindId);
		}
		return null;
	}
	
	@Kroll.method
	public KrollDict getItemAt(int sectionIndex, int itemIndex) {
		TiUIView listView = peekView();
		if (listView != null) {
			return ((TiListView) listView).getItem(sectionIndex, itemIndex);
		} else {
			if (sectionIndex < 0 || sectionIndex >= preloadSections.size()) {
				Log.e(TAG, "getItem Invalid section index");
				return null;
			}
			
			return preloadSections.get(sectionIndex).getItemAt(itemIndex);
		}
	}
	
	
	@Kroll.method
	public void setMarker(Object marker) {
		if (marker instanceof HashMap) {
			HashMap<String, Integer> m = (HashMap<String, Integer>) marker;
			TiUIView listView = peekView();
			if (listView != null) {
				((TiListView)listView).setMarker(m);
			} else {
				preloadMarker = m;
			}
		}
	}
	
	@Kroll.method
	public void scrollToTop(int y, @Kroll.argument(optional = true) KrollDict options)
	{
		boolean animated = TiConvert.toBoolean(options, TiC.PROPERTY_ANIMATED, true);
		Message message = getMainHandler().obtainMessage(MSG_SCROLL_TO_TOP);
		message.arg1 = y;
		message.arg2 = animated?1:0;
		message.sendToTarget();
	}

	@Kroll.method
	public void scrollToBottom(int y, @Kroll.argument(optional = true) KrollDict options)
	{
		boolean animated = TiConvert.toBoolean(options, TiC.PROPERTY_ANIMATED, true);
		Message message = getMainHandler().obtainMessage(MSG_SCROLL_TO_BOTTOM);
		message.arg1 = y;
		message.arg2 = animated?1:0;
		message.sendToTarget();
	}

	@Override
	public boolean handleMessage(final Message msg) 	{

		switch (msg.what) {

			case MSG_SECTION_COUNT: {
				AsyncResult result = (AsyncResult)msg.obj;
				result.setResult(handleSectionCount());
				return true;
			}

			case MSG_SCROLL_TO_ITEM: {
				AsyncResult result = (AsyncResult)msg.obj;
				KrollDict data = (KrollDict) result.getArg();
				int sectionIndex = data.getInt("sectionIndex");
				int itemIndex = data.getInt("itemIndex");
				boolean animated = data.getBoolean("animated");
				handleScrollToItem(sectionIndex, itemIndex, animated);
				result.setResult(null);
				return true;
			}
			case MSG_SCROLL_TO_TOP: {
				handleScrollToTop(msg.arg1, msg.arg2 == 1);
				return true;
			}
			case MSG_SCROLL_TO_BOTTOM: {
				handleScrollToBottom(msg.arg1, msg.arg2 == 1);
				return true;
			}
			case MSG_APPEND_SECTION: {
				handleAppendSection(msg.obj);
				return true;
			}
			case MSG_DELETE_SECTION_AT: {
				handleDeleteSectionAt(TiConvert.toInt(msg.obj));
				return true;
			}
			case MSG_INSERT_SECTION_AT: {
				KrollDict data = (KrollDict) msg.obj;
				int index = data.getInt("index");
				Object section = data.get("section");
				handleInsertSectionAt(index, section);
				return true;
			}
			case MSG_REPLACE_SECTION_AT: {
				KrollDict data = (KrollDict) msg.obj;
				int index = data.getInt("index");
				Object section = data.get("section");
				handleReplaceSectionAt(index, section);
				return true;
			}
			case MSG_SHOW_PULL_VIEW: {
				handleShowPullView(msg.obj);
				return true;
			}
			case MSG_CLOSE_PULL_VIEW: {
				handleClosePullView(msg.obj);
				return true;
			}
			default:
				return super.handleMessage(msg);
		}
	}
	private void handleScrollToItem(int sectionIndex, int itemIndex, boolean animated) {
		TiUIView listView = peekView();
		if (listView != null) {
			((TiListView) listView).scrollToItem(sectionIndex, itemIndex, animated);
		}
	}

	private void handleScrollToTop(int y, boolean animated) {
		TiUIView listView = peekView();
		if (listView != null) {
			((TiListView) listView).scrollToTop(y, animated);
		}
	}

	private void handleScrollToBottom(int y, boolean animated) {
		TiUIView listView = peekView();
		if (listView != null) {
			((TiListView) listView).scrollToBottom(y, animated);
		}
	}

	@Kroll.method
	public void appendSection(Object section) {
		if (TiApplication.isUIThread()) {
			handleAppendSection(section);
		} else {
			Handler handler = getMainHandler();
			handler.sendMessage(handler.obtainMessage(MSG_APPEND_SECTION, section));
		}
	}

	private void handleAppendSection(Object section) {
		TiUIView listView = peekView();
		if (listView != null) {
			((TiListView) listView).appendSection(section);
		} else {
			preload = true;
			addPreloadSections(section, -1, false);
		}
	}
	
	@Kroll.method
	public void deleteSectionAt(int index) {
		if (TiApplication.isUIThread()) {
			handleDeleteSectionAt(index);
		} else {
			Handler handler = getMainHandler();
			handler.sendMessage(handler.obtainMessage(MSG_DELETE_SECTION_AT, index));
		}
	}
	
	private void handleDeleteSectionAt(int index) {
		TiUIView listView = peekView();
		if (listView != null) {
			((TiListView) listView).deleteSectionAt(index);
		} else {
			if (index < 0 || index >= preloadSections.size()) {
				Log.e(TAG, "Invalid index to delete section");
				return;
			}
			preload = true;
			preloadSections.remove(index);
		}
	}
	
	@Kroll.method
	public void insertSectionAt(int index, Object section) {
		if (TiApplication.isUIThread()) {
			handleInsertSectionAt(index, section);
		} else {
			sendInsertSectionMessage(index, section);
		}
	}
	
	private void sendInsertSectionMessage(int index, Object section) {
		Handler handler = getMainHandler();
		KrollDict data = new KrollDict();
		data.put("index", index);
		data.put("section", section);
		handler.sendMessage(handler.obtainMessage(MSG_INSERT_SECTION_AT, data));
	}
	
	private void handleInsertSectionAt(int index, Object section) {
		TiUIView listView = peekView();
		if (listView != null) {
			((TiListView) listView).insertSectionAt(index, section);
		} else {
			if (index < 0 || index > preloadSections.size()) {
				Log.e(TAG, "Invalid index to insertSection");
				return;
			}
			preload = true;
			addPreloadSections(section, index, false);
		}
	}
	
	@Kroll.method
	public void replaceSectionAt(int index, Object section) {
		if (TiApplication.isUIThread()) {
			handleReplaceSectionAt(index, section);
		} else {
			sendReplaceSectionMessage(index, section);
		}
	}
	
	private void sendReplaceSectionMessage(int index, Object section) {
		Handler handler = getMainHandler();
		KrollDict data = new KrollDict();
		data.put("index", index);
		data.put("section", section);
		handler.sendMessage(handler.obtainMessage(MSG_REPLACE_SECTION_AT, data));
	}

	private void handleReplaceSectionAt(int index, Object section) {
		TiUIView listView = peekView();
		if (listView != null) {
			((TiListView) listView).replaceSectionAt(index, section);
		} else {
			handleDeleteSectionAt(index);
			handleInsertSectionAt(index,  section);
			
		}
	}

	@Override
	public String getApiName()
	{
		return "Ti.UI.ListView";
	}
	
	public void handleShowPullView(Object obj) {
		Boolean animated = true;
		if (obj != null) {
			animated = TiConvert.toBoolean(obj);
		}
		TiUIView listView = peekView();
		if (listView != null) {
			((TiListView) listView).showPullView(animated);
		}
	}
	
	public void handleClosePullView(Object obj) {
		Boolean animated = true;
		if (obj != null) {
			animated = TiConvert.toBoolean(obj);
		}
		TiUIView listView = peekView();
		if (listView != null) {
			((TiListView) listView).closePullView(animated);
		}
	}
	
	@Kroll.method()
	public void showPullView(@Kroll.argument(optional = true) Object obj) {
		if (TiApplication.isUIThread()) {
			handleShowPullView(obj);
		} else {
			Handler handler = getMainHandler();
			handler.sendMessage(handler.obtainMessage(MSG_SHOW_PULL_VIEW, obj));
		}
	}
	
	@Kroll.method()
	public void closePullView(@Kroll.argument(optional = true) Object obj) {
		if (TiApplication.isUIThread()) {
			handleClosePullView(obj);
		} else {
			Handler handler = getMainHandler();
			handler.sendMessage(handler.obtainMessage(MSG_CLOSE_PULL_VIEW, obj));
		}
	}
	
	
	@Kroll.method
	public void appendItems(int sectionIndex, Object data) {
		ListSectionProxy section = getSectionAt(sectionIndex);
		if (section != null){
			section.appendItems(data);
		}
		else {
			Log.e(TAG, "appendItems wrong section index");
		}
	}
	
	@Kroll.method
	public void insertItemsAt(int sectionIndex, int index, Object data) {
		ListSectionProxy section = getSectionAt(sectionIndex);
		if (section != null){
			section.insertItemsAt(index, data);
		}
		else {
			Log.e(TAG, "insertItemsAt wrong section index");
		}
	}

	@Kroll.method
	public void deleteItemsAt(int sectionIndex, int index, int count) {
		ListSectionProxy section = getSectionAt(sectionIndex);
		if (section != null){
			section.deleteItemsAt(index, count);
		}
		else {
			Log.e(TAG, "deleteItemsAt wrong section index");
		}
	}

	@Kroll.method
	public void replaceItemsAt(int sectionIndex, int index, int count, Object data) {
		ListSectionProxy section = getSectionAt(sectionIndex);
		if (section != null){
			section.replaceItemsAt(index, count, data);
		}
		else {
			Log.e(TAG, "replaceItemsAt wrong section index");
		}
	}

	@Kroll.method
	public void updateItemAt(int sectionIndex, int index, Object data) {
		ListSectionProxy section = getSectionAt(sectionIndex);
		if (section != null){
			section.updateItemAt(index, data);
		}
		else {
			Log.e(TAG, "updateItemAt wrong section index");
		}
	}
}
