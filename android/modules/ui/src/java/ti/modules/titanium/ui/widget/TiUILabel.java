/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2013 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
package ti.modules.titanium.ui.widget;

import java.util.HashMap;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.titanium.TiC;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.transition.Transition;
import org.appcelerator.titanium.transition.TransitionHelper;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.util.TiHtml;
import org.appcelerator.titanium.util.TiHtml.CustomBackgroundSpan;
import org.appcelerator.titanium.util.TiTypefaceSpan;
import org.appcelerator.titanium.util.TiUIHelper;
import org.appcelerator.titanium.view.FreeLayout;
import org.appcelerator.titanium.view.TiUINonViewGroupView;

import com.nineoldandroids.animation.Animator;
import com.nineoldandroids.animation.AnimatorSet;
import com.nineoldandroids.animation.Animator.AnimatorListener;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.RectF;
import android.text.InputType;
import android.text.TextUtils;
import android.text.util.Linkify;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import android.graphics.Typeface;
import android.text.Layout;
import android.text.Layout.Alignment;
import android.text.Spannable;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.StaticLayout;
import android.text.TextUtils.TruncateAt;
import android.text.style.AbsoluteSizeSpan;
import android.text.style.BackgroundColorSpan;
import android.text.style.BulletSpan;
import android.text.style.ForegroundColorSpan;
import android.text.style.ImageSpan;
import android.text.style.MaskFilterSpan;
import android.text.style.QuoteSpan;
import android.text.style.RasterizerSpan;
import android.text.style.RelativeSizeSpan;
import android.text.style.ScaleXSpan;
import android.text.style.StrikethroughSpan;
import android.text.style.StyleSpan;
import android.text.style.SubscriptSpan;
import android.text.style.SuperscriptSpan;
import android.text.style.TextAppearanceSpan;
import android.text.style.TypefaceSpan;
import android.text.style.URLSpan;
import android.text.style.UnderlineSpan;
import android.util.TypedValue;

@SuppressWarnings({"unchecked", "rawtypes"})
public class TiUILabel extends TiUINonViewGroupView
{
	private static final String TAG = "TiUILabel";
	private static final float DEFAULT_SHADOW_RADIUS = 0.5f;

	private int selectedColor, color, disabledColor, widgetDefaultColor;
	private boolean wordWrap = true;
	private float shadowRadius = DEFAULT_SHADOW_RADIUS;
	private float shadowX = 0f;
	private float shadowY = -1f; // to have the same value as ios
	private int shadowColor = Color.TRANSPARENT;
	

	private RectF textPadding;
	private String ELLIPSIZE_CHAR = "...";

	private TiLabelView tv;
	private HashMap transitionDict = null;
	
	public class TiLabelView extends FreeLayout {

		public EllipsizingTextView textView;
		private EllipsizingTextView oldTextView = null;

		private Transition  queuedTransition = null;
		private AnimatorSet  currentTransitionSet = null;
		private CharSequence  queuedText = null;
		
		@Override
		public void dispatchSetPressed(boolean pressed) {
			int count = getChildCount();
			for (int i = 0; i < count; i++) {
	            final View child = getChildAt(i);
	            child.setPressed(pressed);
	        }
		}
		
		@Override
		protected void drawableStateChanged() {
		
		}
		
		@Override
		public void childDrawableStateChanged(View child) {
			if (child == textView) {
				propagateChildDrawableState(child);
			}
		}
		
		public TiLabelView(Context context) {
			super(context);
			textView = new EllipsizingTextView(context);
			textView.setGravity(Gravity.CENTER_VERTICAL | Gravity.LEFT);
 			textView.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
			textView.setKeyListener(null);
			textView.setSingleLine(false);
			TiUIHelper.styleText(textView, null);
			addView(textView, getTextLayoutParams());
		}
		
//		@SuppressLint("NewApi")
//		private EllipsizingTextView cloneTextView(EllipsizingTextView original, CharSequence text){
//			EllipsizingTextView newView = new EllipsizingTextView(getContext());
//			newView.setInputType(original.getInputType());
//			newView.setGravity(original.getGravity());
//			newView.setKeyListener(original.getKeyListener());
////			TiUIHelper.styleText(newView, getProxy().getProperties().getKrollDict(TiC.PROPERTY_FONT));
//			newView.setEllipsize(original.ellipsize);
//			newView.setSingleLine(original.singleline); //the order is important as setSingleLine also set Maxlines
//			newView.setMaxLines(original.maxLines);
//			newView.setMaxTextSize(original.getMaxTextSize());
//			newView.setMinTextSize(original.getMinTextSize());
//			newView.lineAdditionalVerticalPadding = original.lineAdditionalVerticalPadding;
//			newView.lineSpacingMultiplier = original.lineSpacingMultiplier;
//			newView.setMultiLineEllipsize(original.getMultiLineEllipsize());
//			newView.setTextColor(original.getTextColors());
//			newView.setPadding(original.getPaddingLeft(), original.getPaddingTop(), original.getPaddingRight(), original.getPaddingBottom());
//			newView.setShadowLayer(shadowRadius, shadowX, shadowY, shadowColor);
//			setText(newView, text);
//			newView.SetReadyToEllipsize(true);
//			return newView;
//		}
		
		private ViewGroup.LayoutParams getTextLayoutParams() {
			ViewGroup.LayoutParams params  = new ViewGroup.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT);
			return params;
		}
		
		@Override
	    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
			int maxHeight = 0;
	        int maxWidth = 0;
	        if (textView.getVisibility() != GONE) {
                measureChildWithMargins(textView, widthMeasureSpec, 0, heightMeasureSpec, 0);
                final LayoutParams lp = (LayoutParams) textView.getLayoutParams();
                maxWidth = Math.max(maxWidth,
                		textView.getMeasuredWidth() + lp.leftMargin + lp.rightMargin);
                maxHeight = Math.max(maxHeight,
                		textView.getMeasuredHeight() + lp.topMargin + lp.bottomMargin);                
            }
	        // Account for padding too
	        maxWidth += getPaddingLeft() + getPaddingRight();
	        maxHeight += getPaddingTop() + getPaddingBottom();
	        
	        setMeasuredDimension(resolveSize(maxWidth, widthMeasureSpec),
	                resolveSize(maxHeight, heightMeasureSpec));
	    }

		public void setText(EllipsizingTextView view, CharSequence sequence)
		{
			if (sequence instanceof Spannable)
			{
				view.setText(sequence, TextView.BufferType.SPANNABLE);
			}
			else {
				view.setText(sequence);
			}
		}
		
		public void setText(CharSequence sequence)
		{
			if(textView != null && textView.fullText.equals(sequence)) return;
			Transition transition = (transitionDict != null)?TransitionHelper.transitionFromObject(transitionDict, null, null):null;
			if (transition != null) 
			{
				setTextWithTransition(sequence, transition);
			}
			else {
				setText(textView, sequence);
			}
		}
		
		public void setTextWithTransition(CharSequence text, Transition transition) {
			if (currentTransitionSet != null) {
				queuedTransition = transition;
				queuedText = text;
				return;
			}
			EllipsizingTextView newTextView = textView.clone(text);
			transitionToTextView(newTextView, transition);
		}
		
		private void onTransitionEnd() {
			removeView(oldTextView);
			oldTextView = null;
			currentTransitionSet = null;
			if (queuedText != null) {
				setTextWithTransition(queuedText, queuedTransition);
				queuedTransition = null;
				queuedText = null;
			}
		}
		
		public void cancelCurrentTransition()
		{
			queuedTransition = null;
			queuedText = null;
			currentTransitionSet = null;
		}
		

		public void transitionToTextView(EllipsizingTextView newTextView, Transition transition) {
			oldTextView = textView;
			textView = newTextView;
			newTextView.setVisibility(View.GONE);
			TiUIHelper.addView(this, newTextView, getTextLayoutParams());
			registerForTouch();
			registerForKeyPress();
			
			transition.setTargets(this, newTextView, oldTextView);

			currentTransitionSet = transition.getSet(new AnimatorListener() {
				public void onAnimationEnd(Animator arg0) {	
						onTransitionEnd();
				}

				public void onAnimationCancel(Animator arg0) {
						onTransitionEnd();
				}

				public void onAnimationRepeat(Animator arg0) {
				}

				public void onAnimationStart(Animator arg0) {
				}
			});
			currentTransitionSet.start();
			newTextView.setVisibility(View.VISIBLE);
			requestLayout();
		}
	}

	public class EllipsizingTextView extends TextView {

		private TruncateAt ellipsize = null;
		private TruncateAt multiLineEllipsize = null;
		private boolean isEllipsized;
		private boolean needsEllipsing;
		private boolean needsResizing;
		private boolean singleline = false;
		private boolean readyToEllipsize = false;
		private CharSequence fullText;
		private int maxLines = 0;
		private float lineSpacingMultiplier = 1.0f;
		private float lineAdditionalVerticalPadding = 0.0f;
		private float minTextSize;
		private float maxTextSize;
//		private String textStr;
		
		float lastEllipsizeWidth = -1;
		float lastEllipsizeHeight = -1;
		
		@Override
		protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec)
		{
			int w = MeasureSpec.getSize(widthMeasureSpec);
			int wm = MeasureSpec.getMode(widthMeasureSpec);
			int h = MeasureSpec.getSize(heightMeasureSpec);
			int hm = MeasureSpec.getMode(heightMeasureSpec);
			if (hm == 0) h = 100000;
			
			
			if (w > 0) {
				if (needsResizing) {
					refitText(this.getText().toString(), w);
				}
				updateEllipsize(w - getPaddingLeft() - getPaddingRight(), 
					h - getPaddingTop() - getPaddingBottom());
		//			 Only allow label to exceed the size of parent when it's size behavior with wordwrap disabled
				if (!wordWrap && layoutParams.optionWidth == null && !layoutParams.autoFillsWidth) {
					widthMeasureSpec = MeasureSpec.makeMeasureSpec(w,
						MeasureSpec.UNSPECIFIED);
					heightMeasureSpec = MeasureSpec.makeMeasureSpec(h,
						MeasureSpec.UNSPECIFIED);
				}
			}
			super.onMeasure(widthMeasureSpec, heightMeasureSpec);
			int height =getMeasuredHeight();
			int width =getMeasuredWidth();
		}

		@Override
		public void setPressed(boolean pressed) {
			super.setPressed(pressed);
			if (dispatchPressed == true && childrenHolder != null) {
				int count = childrenHolder.getChildCount();
				for (int i = 0; i < count; i++) {
					final View child = childrenHolder.getChildAt(i);
					child.setPressed(pressed);
				}
			}
		}

		@Override
		public boolean dispatchTouchEvent(MotionEvent event) {
			if (touchPassThrough(childrenHolder, event)) return false;
			if (touchPassThrough == true)
				return false;
			return super.dispatchTouchEvent(event);
		}
		
		public EllipsizingTextView(Context context) {
			super(context);
			maxTextSize = this.getTextSize();
			if (maxTextSize < 35) {
				maxTextSize = 30;
			}
			minTextSize = 20;
			needsResizing = false;
			super.setSingleLine(false);
		}
		
		public EllipsizingTextView clone(CharSequence text) {
			EllipsizingTextView newView = new EllipsizingTextView(getContext());
			newView.setInputType(getInputType());
			newView.setGravity(getGravity());
			newView.setKeyListener(getKeyListener());
			TiUIHelper.styleText(newView, getProxy().getProperties().getKrollDict(TiC.PROPERTY_FONT));
			newView.setEllipsize(ellipsize);
			newView.singleline = this.singleline;
			newView.maxLines = this.maxLines;
			newView.maxTextSize = this.maxTextSize;
			newView.minTextSize = this.minTextSize;
			newView.lineAdditionalVerticalPadding = this.lineAdditionalVerticalPadding;
			newView.lineSpacingMultiplier = this.lineSpacingMultiplier;
			newView.multiLineEllipsize = this.multiLineEllipsize;
			newView.setTextColor(getTextColors());
			newView.setPadding(getPaddingLeft(), getPaddingTop(), getPaddingRight(), getPaddingBottom());
			newView.setShadowLayer(shadowRadius, shadowX, shadowY, shadowColor);
			if (text instanceof Spannable)
			{
				newView.setText(text, TextView.BufferType.SPANNABLE);
			}
			else {
				newView.setText(text);
			}
			newView.SetReadyToEllipsize(true);
			return newView;
		}
		

		public float getMinTextSize() {
			return minTextSize;
		}
		
		public void setMinTextSize(float minTextSize) {
			this.minTextSize = minTextSize;
		}
		
		public float getMaxTextSize() {
			return maxTextSize;
		}
		
		public void setMaxTextSize(float minTextSize) {
			this.maxTextSize = minTextSize;
		}


		public boolean isEllipsized() {
			return isEllipsized;
		}

		public void SetReadyToEllipsize(Boolean value){
			readyToEllipsize = value;
//			if (readyToEllipsize == true)
//				updateEllipsize();
		}

		@Override
		public void setMaxLines(int maxLines) {
			super.setMaxLines(maxLines);
			if (maxLines == Integer.MAX_VALUE) maxLines = 0;
			this.maxLines = maxLines;
			updateEllipsize();
		}
		
		
		public void updateEllipsize(int width, int height){
			if (needsEllipsize())  {
				needsEllipsing = true;
				if (readyToEllipsize == true) ellipseText(width, height);
			}
		}
		
		public void updateEllipsize(){
			updateEllipsize(getMeasuredWidth(), getMeasuredHeight());
		}

		public int getMaxLines() {
			return maxLines;
		}
		
//		private void resetText(){
//			if (isEllipsized){
//				isEllipsized = false;
//				try {
//					setText(fullText);
//				} finally {
//				}
//			}
//		}

		@Override
		public void setLineSpacing(float add, float mult) {
			this.lineAdditionalVerticalPadding = add;
			this.lineSpacingMultiplier = mult;
			super.setLineSpacing(add, mult);
			updateEllipsize();
		}
		
		
		@Override
		public void setTypeface(Typeface tf, int style){
			super.setTypeface(tf, style);
			updateEllipsize();
		}
		
		@Override
		public void setTextSize(int unit, float size){
			super.setTextSize(unit, size);
			updateEllipsize();
		}

		@Override
		public void setText(CharSequence text, BufferType type) {
			fullText = text;
			super.setText(text, type);
			updateEllipsize();
		}

//		@Override
//		protected void onSizeChanged(int w, int h, int oldw, int oldh) {
//			super.onSizeChanged(w, h, oldw, oldh);
//			// updateEllipsize();
//		}
		
		@Override
		public void setPadding(int left, int top, int right, int bottom) {
			super.setPadding(left + (int)Math.max(0, -shadowX), top + (int)Math.max(0, -shadowY), right + (int)Math.max(0, shadowX), bottom + (int)Math.max(0, shadowY));
		}
		
		
		@Override
		public void setSingleLine (boolean singleLine) {
			if (this.singleline == singleLine) return;
			this.singleline = singleLine;
			if (this.maxLines == 1 && singleLine == false){
				//we were at maxLines==1 and singleLine==true
				//it s actually the same thing now so let s not change anything
			}
			else{
				super.setSingleLine(singleLine);
			}
			updateEllipsize();
		}

		@Override
		public void setEllipsize(TruncateAt where) {			
			super.setEllipsize(where);
			ellipsize = where;
			updateEllipsize();
		}
		
		@Override
		protected void onTextChanged(final CharSequence text, final int start,
			final int before, final int after) {
			if (needsResizing) {
				refitText(this.getText().toString(),  this.getWidth());
			}
		}

		public void setMultiLineEllipsize(TruncateAt where) {
			multiLineEllipsize = where;
			updateEllipsize();
		}
		
		public TruncateAt getMultiLineEllipsize() {
			return multiLineEllipsize;
		}
		
		private void refitText(String text, int textWidth) {
			if (textWidth > 0) {
				int availableWidth = textWidth - this.getPaddingLeft()
				- this.getPaddingRight();
				float trySize = maxTextSize;

				this.setTextSize(TypedValue.COMPLEX_UNIT_PX, trySize);
				while ((trySize > minTextSize)
					&& (this.getPaint().measureText(text) > availableWidth)) {
					trySize -= 1;
				if (trySize <= minTextSize) {
					trySize = minTextSize;
					break;
				}
				this.setTextSize(TypedValue.COMPLEX_UNIT_PX, trySize);
			}
			this.setTextSize(TypedValue.COMPLEX_UNIT_PX, trySize);
		}
	}
	
//		private CharSequence ellipsisWithStyle(CharSequence text, TruncateAt where)
//		{
//			int length = ELLIPSIZE_CHAR.length();
//			if (text instanceof Spanned){
//				SpannableStringBuilder builder = new SpannableStringBuilder(text);
//				SpannableStringBuilder htmlText = (SpannableStringBuilder) text;
//				if (where == TruncateAt.END){
//					Object[] spans = htmlText.getSpans(text.length() - 1, text.length(), Object.class);
//					builder.append(ELLIPSIZE_CHAR);
//					for (int i = 0; i < spans.length; i++) {
//						int flags = htmlText.getSpanFlags(spans[i]);
//						int start = htmlText.getSpanStart(spans[i]);
//						int end = htmlText.getSpanEnd(spans[i]);
//						builder.setSpan(spans[i], start, end + length, flags);
//					}
//				}
//				else if (where == TruncateAt.START){
//					Object[] spans = htmlText.getSpans(0, 1, Object.class);
//					builder.insert(0, ELLIPSIZE_CHAR);
//					for (int i = 0; i < spans.length; i++) {
//						int flags = htmlText.getSpanFlags(spans[i]);
//						int start = htmlText.getSpanStart(spans[i]);
//						int end = htmlText.getSpanEnd(spans[i]);
//						builder.setSpan(spans[i], start, end + length, flags);
//					}
//				}
//				else if (where == TruncateAt.MIDDLE){
//					int middle = (int) Math.floor(htmlText.length() / 2);
//					Object[] spans = htmlText.getSpans(middle-1, middle, Object.class);
//					builder.insert(middle, ELLIPSIZE_CHAR);
//					for (int i = 0; i < spans.length; i++) {
//						int flags = htmlText.getSpanFlags(spans[i]);
//						int start = htmlText.getSpanStart(spans[i]);
//						int end = htmlText.getSpanEnd(spans[i]);
//						builder.setSpan(spans[i], start, end + length, flags);
//					}
//				}
//				return builder;
//			}
//			else {
//				if (where == TruncateAt.END){
//					return TextUtils.concat(text, ELLIPSIZE_CHAR);
//				}
//				else if (where == TruncateAt.START){
//					return TextUtils.concat(ELLIPSIZE_CHAR , text);
//
//				}
//				else if (where == TruncateAt.MIDDLE){
//					int middle = (int) Math.floor(text.length() / 2);
//					return TextUtils.concat(text.subSequence(0, middle), ELLIPSIZE_CHAR, text.subSequence(middle, text.length()));
//				}
//			}
//			return text;
//		}
		
		private CharSequence strimText(CharSequence text)
		{
			int strimEnd = text.toString().trim().length();
			if (strimEnd != text.length()){
				return text.subSequence(0, strimEnd);
			}
			return text;
		}
		
		private CharSequence getEllipsedTextForOneLine(CharSequence text, TruncateAt where, int width){
			CharSequence newText = strimText(text);				
			int length = ELLIPSIZE_CHAR.length();
			if (where == TruncateAt.START || where == TruncateAt.END){
				if (where == TruncateAt.START) {
					newText = TextUtils.concat(ELLIPSIZE_CHAR, newText);
				}
				else if(where == TruncateAt.END) {
					newText = TextUtils.concat(newText, ELLIPSIZE_CHAR);
				}
				newText = TextUtils.ellipsize(newText, getPaint(), width, where);
				if (newText.length() <= length) return newText;
				String textStr = newText.toString();
				if (where == TruncateAt.START && !textStr.startsWith(ELLIPSIZE_CHAR)) {
					newText = TextUtils.concat(ELLIPSIZE_CHAR, newText.subSequence(length, textStr.length()));
				}
				else if(where == TruncateAt.END && !textStr.endsWith(ELLIPSIZE_CHAR)) {
					newText = TextUtils.concat(newText.subSequence(0, textStr.length() - length), ELLIPSIZE_CHAR);
				}
			}
			else {
				CharSequence newTextLeft = TextUtils.ellipsize(newText, getPaint(), width/2, TruncateAt.END);
				CharSequence newTextRight = TextUtils.ellipsize(newText, getPaint(), width/2, TruncateAt.START);
				String textLeftStr = newTextLeft.toString();
				String textRightStr = newTextRight.toString();
				if (textLeftStr.length() == 0 || (
						textLeftStr.length() + textRightStr.length() == newText.toString().length())) return newText;
				if (!textLeftStr.endsWith(ELLIPSIZE_CHAR)) {
					newTextLeft = TextUtils.concat(ELLIPSIZE_CHAR, newTextLeft.subSequence(length, textLeftStr.length()));
				}
				if (textRightStr.startsWith(ELLIPSIZE_CHAR)) {
					newTextRight = (CharSequence) newTextRight.subSequence(length, newTextRight.length());
				}
				newText = TextUtils.concat(newTextLeft, newTextRight);
			}
			return newText;

		}
		
		// @SuppressLint("NewApi")
		private Object duplicateSpan(Object span){
			if (span instanceof ForegroundColorSpan){
				return new ForegroundColorSpan(((ForegroundColorSpan)span).getForegroundColor());
			}
			if (span instanceof BackgroundColorSpan){
				return new BackgroundColorSpan(((BackgroundColorSpan)span).getBackgroundColor());
			}
			else if (span instanceof AbsoluteSizeSpan){
				return new AbsoluteSizeSpan(((AbsoluteSizeSpan)span).getSize(), ((AbsoluteSizeSpan)span).getDip());
			}
			else if (span instanceof RelativeSizeSpan){
				return new RelativeSizeSpan(((RelativeSizeSpan)span).getSizeChange());
			}
			else if (span instanceof TextAppearanceSpan){
				return new TextAppearanceSpan(((TextAppearanceSpan)span).getFamily(), ((TextAppearanceSpan)span).getTextStyle(), ((TextAppearanceSpan)span).getTextSize(), ((TextAppearanceSpan)span).getTextColor(), ((TextAppearanceSpan)span).getLinkTextColor());
			}
			else if (span instanceof URLSpan){
				return new URLSpan(((URLSpan)span).getURL());
			}
			else if (span instanceof UnderlineSpan){
				return new UnderlineSpan();
			}
			else if (span instanceof SuperscriptSpan){
				return new SuperscriptSpan();
			}
			else if (span instanceof SubscriptSpan){
				return new SubscriptSpan();
			}
			else if (span instanceof StrikethroughSpan){
				return new StrikethroughSpan();
			}
			else if (span instanceof BulletSpan){
				return new BulletSpan();
			}
//			else if (span instanceof ClickableSpan){
//				return new ClickableSpan();
//			}
			else if (span instanceof ScaleXSpan){
				return new ScaleXSpan(((ScaleXSpan)span).getScaleX());
			}
			else if (span instanceof StyleSpan){
				return new StyleSpan(((StyleSpan)span).getStyle());
			}
			else if (span instanceof TypefaceSpan){
				return new TypefaceSpan(((TypefaceSpan)span).getFamily());
			}
			else if (span instanceof TiTypefaceSpan){
				return new TiTypefaceSpan(((TypefaceSpan)span).getFamily());
			}
			else if (span instanceof ImageSpan){
				return new ImageSpan(((ImageSpan)span).getDrawable());
			}
			else if (span instanceof RasterizerSpan){
				return new RasterizerSpan(((RasterizerSpan)span).getRasterizer());
			}
			else if (span instanceof QuoteSpan){
				return new QuoteSpan(((QuoteSpan)span).getColor());
			}
			else if (span instanceof MaskFilterSpan){
				return new MaskFilterSpan(((MaskFilterSpan)span).getMaskFilter());
			}
			else if (span instanceof CustomBackgroundSpan){
				return new CustomBackgroundSpan(((CustomBackgroundSpan)span));
			}
			
			return null;
		}
		
		public boolean needsEllipsize(){
			return fullText != null && fullText.length() > 0 && (ellipsize != null || multiLineEllipsize != null);
		}

		private void ellipseText(int width, int height) {
			if (!needsEllipsize() || needsEllipsing == false
					|| (width <= 0) || (height <= 0)) return;
//			if (width == lastEllipsizeWidth && height == lastEllipsizeHeight)
//			{
//				needsEllipsing = false;
//				return;
//			}
			boolean ellipsized = false;
			CharSequence workingText = fullText;

			if (fullText instanceof Spanned){
				SpannableStringBuilder htmlWorkingText = new SpannableStringBuilder(fullText);
				if (this.singleline == false && multiLineEllipsize != null) {
					SpannableStringBuilder newText = new SpannableStringBuilder();
					String str = htmlWorkingText.toString();
					String[] separated = str.split("\n");
					int start = 0;
					int newStart = 0;
					for (int i = 0; i < separated.length; i++) {
						String linestr = separated[i];
						int end = start +  linestr.length();
						if (linestr.length() > 0){
							SpannableStringBuilder lineSpanned = (SpannableStringBuilder) htmlWorkingText.subSequence(start, end);
							Object[] spans = lineSpanned.getSpans(0, lineSpanned.length(), Object.class);
							
							//this is a trick to get the Spans for the last line to be used in getEllipsedTextForOneLine
							//we append,setSpans, getlastline with spans, ellipse, replace last line with last line ellipsized
							newText.append(lineSpanned.toString());
							for (int j = 0; j < spans.length; j++) {
								int start2 = htmlWorkingText.getSpanStart(spans[j]);
								int end2 = htmlWorkingText.getSpanEnd(spans[j]);
								int mystart = newStart + Math.max(0, start2 - start);
								int spanlengthonline = Math.min(end2, start + linestr.length()) - Math.max(start2, start);
								int myend = Math.min(mystart + spanlengthonline, newStart + lineSpanned.length());
								int flags = htmlWorkingText.getSpanFlags(spans[j]);
								if (myend > mystart){
									Object newSpan = duplicateSpan(spans[j]);
									newText.setSpan(newSpan, mystart, myend, flags);
								}
							}

							CharSequence lastLine = newText.subSequence(newStart, newStart + lineSpanned.length());
							if (createWorkingLayout(lastLine, width).getLineCount() > 1) 
								lastLine = getEllipsedTextForOneLine(lastLine, multiLineEllipsize, width);

							newText.replace(newStart, newStart + lineSpanned.length(), lastLine);
						}
						if (i < (separated.length - 1)) newText.append('\n');
						start = end + 1;
						newStart = newText.length();
					}
					workingText = newText;
				}
				else {
					Layout layout = createWorkingLayout(workingText, width);
					int linesCount = getLinesCount(layout, height);
					if (layout.getLineCount() > linesCount && ellipsize != null) {
						if (linesCount >= 2) {
							int start2 = layout.getLineStart(linesCount - 1);
							int end1 = layout.getLineEnd(linesCount - 2);
							int end2 = layout.getLineEnd(linesCount - 1);
							SpannableStringBuilder newText = new SpannableStringBuilder();
							newText.append(fullText.subSequence(0, end1));
							// We have more lines of text than we are allowed to display.
							newText.append(getEllipsedTextForOneLine(fullText.subSequence(start2, end2), ellipsize, width));
							workingText = newText;
						} else {
							workingText = getEllipsedTextForOneLine(fullText.subSequence(0, layout.getLineEnd(linesCount - 1)), ellipsize, width);
						}
					}
				}
			}
			else {
				if (this.singleline == false && multiLineEllipsize != null) {
					String str = workingText.toString();
					String newText = new String();
					String[] separated = str.split("\n");
					for (int i = 0; i < separated.length; i++) {
						String linestr = separated[i];
						if (linestr.length() > 0){
							if (createWorkingLayout(linestr, width).getLineCount() > 1)
								newText += getEllipsedTextForOneLine(linestr, multiLineEllipsize, width);
							else
								newText += linestr;
						}
						if (i < (separated.length - 1)) 
							newText += '\n';
					}
					workingText = newText;
				}
				else {
					Layout layout = createWorkingLayout(workingText, width);
					int linesCount = getLinesCount(layout, height);
					if (layout.getLineCount() > linesCount && ellipsize != null) {
						if (linesCount >= 2) {
							int start2 = layout.getLineStart(linesCount - 1);
							int end1 = layout.getLineEnd(linesCount - 2);
							int end2 = layout.getLineEnd(linesCount - 1);
							SpannableStringBuilder newText = new SpannableStringBuilder();
							newText.append(fullText.subSequence(0, end1));
							// We have more lines of text than we are allowed to display.
							newText.append(getEllipsedTextForOneLine(fullText.subSequence(start2, end2), ellipsize, width));
							workingText = newText;
						} else {
							workingText = getEllipsedTextForOneLine(fullText.subSequence(0, layout.getLineEnd(linesCount - 1)), ellipsize, width);
						}
						
					}
				}
			}
			
			
			if (!workingText.equals(getText())) {
				try {
					super.setText(workingText, TextView.BufferType.SPANNABLE);
				} finally {
					ellipsized = true;
					
				}
			}
			needsEllipsing = false;
			lastEllipsizeWidth = width;
			lastEllipsizeHeight = height;
			if (ellipsized != isEllipsized) {
				isEllipsized = ellipsized;
			}
		}

		/**
		* Get how many lines of text we are allowed to display.
		*/
//		private int getLinesCount(int width, int height) {
//			int fullyVisibleLinesCount = getFullyVisibleLinesCount(width, height);
//			if (fullyVisibleLinesCount == -1) {
//				return fullyVisibleLinesCount = 1;
//			}
//			return (maxLines == 0)?fullyVisibleLinesCount:Math.min(maxLines, fullyVisibleLinesCount);
//		}

		private int getLinesCount(Layout layout, int height) {
			int fullyVisibleLinesCount = getFullyVisibleLinesCount(layout, height);
			if (fullyVisibleLinesCount == -1) {
				return fullyVisibleLinesCount = 1;
			}
			return (maxLines == 0)?fullyVisibleLinesCount:Math.min(maxLines, fullyVisibleLinesCount);
		}

		/**
		* Get how many lines of text we can display so their full height is visible.
		*/
//		private int getFullyVisibleLinesCount(int width, int height) {
//			Layout layout = createWorkingLayout(fullText, width);
//			return getFullyVisibleLinesCount(layout, height);
//		}

		private int getFullyVisibleLinesCount(Layout layout, int height) {
			int totalLines = layout.getLineCount();
			int index = totalLines - 1;
			int lineHeight = layout.getLineBottom(index);
			while(lineHeight > height) {
				index -= 1;
				lineHeight = layout.getLineBottom(index);
			}
			return index + 1;
		}

		private Layout createWorkingLayout(CharSequence workingText, int width) {
			return new StaticLayout(workingText, getPaint(),
				width,
				Alignment.ALIGN_NORMAL, lineSpacingMultiplier,
				lineAdditionalVerticalPadding, false /* includepad */);
		}
		
		public int getOffsetForPosition(float x, float y) {
	        if (getLayout() == null) return -1;
	        final int line = getLineAtCoordinate(y);
	        final int offset = getOffsetAtCoordinate(line, x);
	        return offset;
	    }

	    float convertToLocalHorizontalCoordinate(float x) {
	        x -= getTotalPaddingLeft();
	        // Clamp the position to inside of the view.
	        x = Math.max(0.0f, x);
	        x = Math.min(getWidth() - getTotalPaddingRight() - 1, x);
	        x += getScrollX();
	        return x;
	    }

	    int getLineAtCoordinate(float y) {
	        y -= getTotalPaddingTop();
	        // Clamp the position to inside of the view.
	        y = Math.max(0.0f, y);
	        y = Math.min(getHeight() - getTotalPaddingBottom() - 1, y);
	        y += getScrollY();
	        return getLayout().getLineForVertical((int) y);
	    }
	    
	    private int getOffsetAtCoordinate(int line, float x) {
	        x = convertToLocalHorizontalCoordinate(x);
	        return getLayout().getOffsetForHorizontal(line, x);
	    }
	}


	public TiUILabel(final TiViewProxy proxy)
	{
		super(proxy);
		Log.d(TAG, "Creating a text label", Log.DEBUG_MODE);
		tv = new TiLabelView(getProxy().getActivity()) {
			@Override
			protected void onLayout(boolean changed, int left, int top, int right, int bottom)
			{
				super.onLayout(changed, left, top, right, bottom);
				TiUIHelper.firePostLayoutEvent(TiUILabel.this);
			}
		};
		textPadding = new RectF();
		
		tv.setFocusable(false);
		widgetDefaultColor = color = disabledColor = selectedColor = tv.textView.getCurrentTextColor();
		setNativeView(tv);

	}

	private Spanned fromHtml(String str)
	{
		SpannableStringBuilder htmlText = new SpannableStringBuilder(TiHtml.fromHtml(str));
		return htmlText;
	}
	
	private void updateTextColors() {
		int[][] states = new int[][] {
			TiUIHelper.BACKGROUND_DISABLED_STATE, // disabled
			TiUIHelper.BACKGROUND_SELECTED_STATE, // pressed
			TiUIHelper.BACKGROUND_FOCUSED_STATE,  // pressed
			TiUIHelper.BACKGROUND_CHECKED_STATE,  // pressed
			new int [] {android.R.attr.state_pressed},  // pressed
			new int [] {android.R.attr.state_focused},  // pressed
			new int [] {}
		};

		ColorStateList colorStateList = new ColorStateList(
			states,
			new int[] {disabledColor, selectedColor, selectedColor, selectedColor, selectedColor, selectedColor, color}
		);

		tv.textView.setTextColor(colorStateList);
	}
	
	protected void makeLinkClickable(SpannableStringBuilder strBuilder, URLSpan span)
	{
//	    int start = strBuilder.getSpanStart(span);
//	    int end = strBuilder.getSpanEnd(span);
//	    int flags = strBuilder.getSpanFlags(span);
//	    URLSpan clickable = new URLSpan(span.getURL()) {
//	          public void onClick(View view) {
//	             if (hasListeners(TiC.EVENT_LINK)) {
//	     			KrollDict data = new KrollDict();
//	     			data.put(TiC.EVENT_PROPERTY_URL,  getURL());
//	     			fireEvent(TiC.EVENT_LINK, data);
//	     		}
//	          }
//	    };
//	    strBuilder.setSpan(clickable, start, end, flags);
//	    strBuilder.removeSpan(span);
	}
	
	protected Spanned prepareHtml(String html)
	{
//	    CharSequence sequence = fromHtml(html);
//	        SpannableStringBuilder strBuilder = new SpannableStringBuilder(sequence);
//	        URLSpan[] urls = strBuilder.getSpans(0, sequence.length(), URLSpan.class);   
//	        for(URLSpan span : urls) {
//	            makeLinkClickable(strBuilder, span);
//	        }
	    return fromHtml(html);       
	}

	@Override
	public void processProperties(KrollDict d)
	{

		super.processProperties(d);
		if (tv == null) return;
		EllipsizingTextView textView = tv.textView;
		textView.SetReadyToEllipsize(false);

		// Clear any text style left over here if view is recycled
//		TiUIHelper.styleText(tv, null, null, null);
		
		boolean needShadow = false;

		boolean needsColors = false;
		if(d.containsKey(TiC.PROPERTY_COLOR)) {
			needsColors = true;
			color = selectedColor = disabledColor = d.optColor(TiC.PROPERTY_COLOR, widgetDefaultColor);
		}
		if(d.containsKey(TiC.PROPERTY_SELECTED_COLOR)) {
			needsColors = true;
			selectedColor = d.optColor(TiC.PROPERTY_SELECTED_COLOR, widgetDefaultColor);
		}
		if(d.containsKey(TiC.PROPERTY_DISABLED_COLOR)) {
			needsColors = true;
			disabledColor = d.optColor(TiC.PROPERTY_DISABLED_COLOR, widgetDefaultColor);
		}
		if (needsColors) {
			updateTextColors();
		}
		
		if (d.containsKey(TiC.PROPERTY_HIGHLIGHTED_COLOR)) {
			textView.setHighlightColor(TiConvert.toColor(d, TiC.PROPERTY_HIGHLIGHTED_COLOR));
		}
		if (d.containsKey(TiC.PROPERTY_FONT)) {
			TiUIHelper.styleText(textView, d.getKrollDict(TiC.PROPERTY_FONT));
		}
		if (d.containsKey(TiC.PROPERTY_TEXT_ALIGN) || d.containsKey(TiC.PROPERTY_VERTICAL_ALIGN)) {
			String textAlign = d.optString(TiC.PROPERTY_TEXT_ALIGN, "left");
			String verticalAlign = d.optString(TiC.PROPERTY_VERTICAL_ALIGN, "middle");
			TiUIHelper.setAlignment(textView, textAlign, verticalAlign);
		}
		if (d.containsKey(TiC.PROPERTY_ELLIPSIZE)) {
			Object value = d.get(TiC.PROPERTY_ELLIPSIZE);
			if (value instanceof Boolean) {
				textView.setEllipsize(((Boolean)value)?TruncateAt.END:null);
			}
			else {
				String str = TiConvert.toString(value);
				if (str != null && !str.equals("none")) //none represents TEXT_ELLIPSIS_NONE
					textView.setEllipsize(TruncateAt.valueOf(str));
				else
					textView.setEllipsize(null);
			}
		}
		if (d.containsKey(TiC.PROPERTY_MULTILINE_ELLIPSIZE)) {
			Object value = d.get(TiC.PROPERTY_MULTILINE_ELLIPSIZE);
			if (value instanceof Boolean) {
				textView.setMultiLineEllipsize(((Boolean)value)?TruncateAt.END:null);
			}
			else {
				String str = TiConvert.toString(value);
				if (str != null && !str.equals("none")) //none represents TEXT_ELLIPSIS_NONE
					textView.setMultiLineEllipsize(TruncateAt.valueOf(str));
				else
					textView.setMultiLineEllipsize(null);
			}
		}
		if (d.containsKey(TiC.PROPERTY_WORD_WRAP)) {
			wordWrap = TiConvert.toBoolean(d, TiC.PROPERTY_WORD_WRAP, true);
			textView.setSingleLine(!wordWrap);
		}
		if (d.containsKey(TiC.PROPERTY_MAX_LINES)) {
			textView.setMaxLines(TiConvert.toInt(d, TiC.PROPERTY_MAX_LINES));
		}
		
		if (d.containsKey(TiC.PROPERTY_SHADOW_OFFSET)) {
			Object value = d.get(TiC.PROPERTY_SHADOW_OFFSET);
			if (value instanceof HashMap) {
				needShadow = true;
				HashMap dict = (HashMap) value;
				shadowX = TiUIHelper.getRawSizeOrZero(dict.get(TiC.PROPERTY_X));
				shadowY = TiUIHelper.getRawSizeOrZero(dict.get(TiC.PROPERTY_Y));
			}
		}
		if (d.containsKey(TiC.PROPERTY_SHADOW_RADIUS)) {
			needShadow = true;
			shadowRadius = TiConvert.toFloat(d.get(TiC.PROPERTY_SHADOW_RADIUS), DEFAULT_SHADOW_RADIUS);
		}
		if (d.containsKey(TiC.PROPERTY_SHADOW_COLOR)) {
			needShadow = true;
			shadowColor = TiConvert.toColor(d, TiC.PROPERTY_SHADOW_COLOR);
		}
		if (needShadow) {
			textView.setShadowLayer(shadowRadius, shadowX, shadowY, shadowColor);
		}
		if (d.containsKey(TiC.PROPERTY_TEXT_PADDING)) {
			textPadding = TiConvert.toPaddingRect(d, TiC.PROPERTY_TEXT_PADDING);
		}
		if(d.containsKey(TiC.PROPERTY_TRANSITION)) {
			Object value = d.get(TiC.PROPERTY_TRANSITION);
			if (value instanceof HashMap) {
				transitionDict = (HashMap) value;
			}
			else {
				transitionDict = null;
			}
		}
		//always set padding as shadowlayer is also using it
		TiUIHelper.setPadding(textView, textPadding);

		// Only accept one, prefer text to title.
		String html = TiConvert.toString(d, TiC.PROPERTY_HTML);
		String text = TiConvert.toString(d, TiC.PROPERTY_TEXT);
		String title = TiConvert.toString(d, TiC.PROPERTY_TITLE);

		if (html != null) {
			tv.setText(prepareHtml(html));
		} else if (title != null) {
			tv.setText(prepareHtml(title));
		} else if (text != null) {
			tv.setText(text);
		}
		TiUIHelper.linkifyIfEnabled(textView, d.get(TiC.PROPERTY_AUTO_LINK));
//		textView.setMovementMethod(LinkMovementMethod.getInstance());
		textView.SetReadyToEllipsize(true);
		// This needs to be the last operation.
		textView.requestLayout();
	}
	
	@Override
	public void propertyChanged(String key, Object oldValue, Object newValue, KrollProxy proxy)
	{
		EllipsizingTextView textView = tv.textView;
		if (key.equals(TiC.PROPERTY_HTML)) {
			String html = TiConvert.toString(newValue);
			if (html == null) {
				html = "";
			}
			tv.setText(prepareHtml(html));
			TiUIHelper.linkifyIfEnabled(textView, proxy.getProperty(TiC.PROPERTY_AUTO_LINK));
			textView.requestLayout();
		} else if (key.equals(TiC.PROPERTY_TEXT) || key.equals(TiC.PROPERTY_TITLE)) {
			String text = TiConvert.toString(newValue);
			if (text == null) {
				text = "";
			}
			tv.setText(text);
			TiUIHelper.linkifyIfEnabled(textView, proxy.getProperty(TiC.PROPERTY_AUTO_LINK));
			textView.requestLayout();
		} else if (key.equals(TiC.PROPERTY_COLOR)) {
			this.color = TiConvert.toColor(newValue);
			updateTextColors();
		} else if (key.equals(TiC.PROPERTY_SELECTED_COLOR)) {
			this.selectedColor = TiConvert.toColor(newValue);
			updateTextColors();
		} else if (key.equals(TiC.PROPERTY_DISABLED_COLOR)) {
			this.disabledColor = TiConvert.toColor(newValue);
			updateTextColors();
		} else if (key.equals(TiC.PROPERTY_HIGHLIGHTED_COLOR)) {
			textView.setHighlightColor(TiConvert.toColor((String) newValue));
		} else if (key.equals(TiC.PROPERTY_TEXT_ALIGN)) {
			TiUIHelper.setAlignment(textView, TiConvert.toString(newValue), null);
			textView.requestLayout();
		} else if (key.equals(TiC.PROPERTY_VERTICAL_ALIGN)) {
			TiUIHelper.setAlignment(textView, null, TiConvert.toString(newValue));
			tv.requestLayout();
		} else if (key.equals(TiC.PROPERTY_FONT)) {
			TiUIHelper.styleText(textView, (HashMap) newValue);
			tv.requestLayout();
		} else if (key.equals(TiC.PROPERTY_ELLIPSIZE)) {
			if (newValue instanceof Boolean) {
				textView.setEllipsize(((Boolean)newValue)?TruncateAt.END:null);
			}
			else {
				String str = TiConvert.toString(newValue);
				if (str != null && !str.equals("none")) //none represents TEXT_ELLIPSIS_NONE
					textView.setEllipsize(TruncateAt.valueOf(str));
				else
					textView.setEllipsize(null);
			}
		} else if (key.equals(TiC.PROPERTY_MULTILINE_ELLIPSIZE)) {
			if (newValue instanceof Boolean) {
				textView.setMultiLineEllipsize(((Boolean)newValue)?TruncateAt.END:null);
			}
			else {
				String str = TiConvert.toString(newValue);
				if (str != null && !str.equals("none")) //none represents TEXT_ELLIPSIS_NONE
					textView.setMultiLineEllipsize(TruncateAt.valueOf(str));
				else
					textView.setMultiLineEllipsize(null);
			}
		} else if (key.equals(TiC.PROPERTY_WORD_WRAP)) {
			textView.setSingleLine(!TiConvert.toBoolean(newValue, true));
		} else if (key.equals(TiC.PROPERTY_MAX_LINES)) {
			textView.setMaxLines(TiConvert.toInt(newValue));
		} else if (key.equals(TiC.PROPERTY_AUTO_LINK)) {
			Linkify.addLinks(textView, TiConvert.toInt(newValue));
		} else if (key.equals(TiC.PROPERTY_TITLE_PADDING)) {
			textPadding = TiConvert.toPaddingRect(newValue);
			TiUIHelper.setPadding(textView, textPadding);
			textView.requestLayout();
		} else if (key.equals(TiC.PROPERTY_SHADOW_OFFSET)) {
			if (newValue instanceof HashMap) {
				HashMap dict = (HashMap) newValue;
				shadowX = TiUIHelper.getRawSizeOrZero(dict.get(TiC.PROPERTY_X));
				shadowY = TiUIHelper.getRawSizeOrZero(dict.get(TiC.PROPERTY_Y));
				textView.setShadowLayer(shadowRadius, shadowX, shadowY, shadowColor);
				TiUIHelper.setPadding(textView, textPadding);
			}
		} else if (key.equals(TiC.PROPERTY_SHADOW_RADIUS)) {
			shadowRadius = TiConvert.toFloat(newValue, DEFAULT_SHADOW_RADIUS);
			textView.setShadowLayer(shadowRadius, shadowX, shadowY, shadowColor);
		} else if (key.equals(TiC.PROPERTY_SHADOW_COLOR)) {
			shadowColor = TiConvert.toColor(TiConvert.toString(newValue));
			textView.setShadowLayer(shadowRadius, shadowX, shadowY, shadowColor);
		} else if (key.equals(TiC.PROPERTY_TRANSITION)) {
			if (newValue instanceof HashMap) {
				transitionDict = (HashMap) newValue;
			}
			else {
				transitionDict = null;
			}
		} else {
			super.propertyChanged(key, oldValue, newValue, proxy);
		}
	}

	public void setClickable(boolean clickable) {
		tv.setClickable(clickable);
	}
	
	@SuppressLint("NewApi")
	@Override
	protected KrollDict dictFromEvent(MotionEvent e)
	{
		KrollDict data = super.dictFromEvent(e);
		CharSequence text = tv.textView.getText();
		if (text instanceof Spanned)
		{
			int[] coords = new int[2];
			getTouchView().getLocationInWindow(coords);

			final double rawx = e.getRawX();
			final double rawy = e.getRawY();
			final double x = (double) rawx - coords[0];
			final double y = (double) rawy - coords[1];
			int offset = tv.textView.getOffsetForPosition((float)x, (float)y);
	        URLSpan[] urls =((Spanned)text).getSpans(offset, offset + 1, URLSpan.class); 
	        if (urls != null && urls.length > 0)
	        {
	        	data.put(TiC.PROPERTY_LINK, urls[0].getURL());
	        }
		}
		 
		return data;
	}
	
	@Override
	protected View getTouchView()
	{
		if (tv != null) {
			return tv.textView;
		}
		return null;
	}
	
	
	@Override
	public void setReusing(boolean value)
	{
		super.setReusing(value);
		if (value)
		{
			if (tv != null) {
				tv.cancelCurrentTransition();
			}
		}
	}
}
