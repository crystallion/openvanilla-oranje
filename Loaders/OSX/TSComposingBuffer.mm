// TSComposingBuffer.cpp

#include <Carbon/Carbon.h>
#include "ATSComponent.h"
#include "TSComposingBuffer.h"

TSComposingBuffer::TSComposingBuffer(ComponentInstance i)
{
    inst=i;
    lastupdate=0;
    str=[NSMutableString new];
}

TSComposingBuffer::~TSComposingBuffer()
{
    [str release];
}

TSComposingBuffer* TSComposingBuffer::clear()
{
    NSRange r;
    r.length=[str length];
    r.location=0;    
    [str deleteCharactersInRange: r];
    lastupdate=0;
    return this;
}

TSComposingBuffer* TSComposingBuffer::send()
{
    if (!isEmpty()) update(TRUE);
    return clear();
}

Boolean TSComposingBuffer::isEmpty()
{
    return [str length] ? FALSE : TRUE;
}

NSMutableString* TSComposingBuffer::getContent()
{
    return str;
}

TSComposingBuffer* TSComposingBuffer::append(NSString *s)
{
    if (s) [str appendString: s];
    return this;
}

int TSComposingBuffer::realPos(int p)
{
    int rp=0;
    unsigned int i;
    
    for (i=0; i<[str length]; i++)
    {
        if (rp==p) break;

        // see if encounters a surrogate pair
        UniChar c=[str characterAtIndex: i];
        if (c >= 0xd800 && c < 0xdc00)
        {
            c=[str characterAtIndex: ++i];
            if (i<[str length] && c >= 0xdc00 && c < 0xe000) rp++;
        }
        else rp++;
    }
    
    return i;    
}

Point TSComposingBuffer::getAppCursorPosition()
{
    Point pnt;	
	long refcon=0, offset=0;
	Boolean edge=0;
	EventRef event=NULL;
	OSStatus status;
	
	// define an ASSERT macro here for getAppCursorPosition (GACP)
	#define GACPASSERT(x)  if ((status=x) != noErr) return pnt;
	
	GACPASSERT(CreateEvent(NULL, kEventClassTextInput, 
	   kEventTextInputOffsetToPos, GetCurrentEventTime(), 
	   kEventAttributeUserEvent, &event));

	ScriptLanguageRecord record;
	bzero(&record, sizeof(record));
	pnt.h = pnt.v = 0;

	#define EVENTPARAM(a, b, c, d) \
	   GACPASSERT(SetEventParameter(event, a, b, sizeof(c), d));

	EVENTPARAM(kEventParamTextInputSendComponentInstance, 
		typeComponentInstance, ComponentInstance, &inst);
	EVENTPARAM(kEventParamTextInputSendRefCon, typeLongInteger, long, &refcon);
	EVENTPARAM(kEventParamTextInputSendTextOffset, typeLongInteger, long, &offset);
	EVENTPARAM(kEventParamTextInputSendSLRec, typeIntlWritingCode, 
		ScriptLanguageRecord, &record);
	EVENTPARAM(kEventParamTextInputSendLeadingEdge, typeBoolean, Boolean, &edge);
    GACPASSERT(SendTextInputEvent(event));
    GACPASSERT(GetEventParameter(event, 
        kEventParamTextInputReplyPoint, typeQDPoint, NULL, sizeof(Point), 
		NULL, &pnt));
			
    if (event) ReleaseEvent(event);    
    return pnt;
    
    #undef EVENTPARAM
    #undef GACPASSERT
}

// Apple's terminolgy calls it "session fix"
TSComposingBuffer* TSComposingBuffer::update(Boolean send, int cursor,
    int markFrom, int markTo)
{
    OSErr error=noErr;
    UniChar *buf=NULL;
    long reallen=[str length]*sizeof(UniChar);
    long fixlen=0;
    EventRef event=NULL;
    ScriptLanguageRecord script;
    TextRange pinrange;
    TextRangeArrayPtr markrange=nil, updaterange=nil;

    if (send) fixlen=reallen;

    // define an ASSERT macro here (U=update)
    #define UASSERT(x)  if ((error=x) != noErr) { clear(); \
        if (buf) { delete[] buf; } \
        return this; }

    UASSERT(CreateEvent(NULL, kEventClassTextInput, 
        kEventTextInputUpdateActiveInputArea,
        GetCurrentEventTime(), kEventAttributeUserEvent, &event));

    // first parameter: reference to our text service component's instance
    UASSERT(SetEventParameter(event, kEventParamTextInputSendComponentInstance,
        typeComponentInstance, sizeof(ComponentInstance),
        &inst));

    // second parameter: script information 
    script.fScript=ATSCSCRIPT;
    script.fLanguage=ATSCLANGUAGE;

    UASSERT(SetEventParameter(event, kEventParamTextInputSendSLRec,
        typeIntlWritingCode, sizeof(ScriptLanguageRecord), &script));

    buf=new UniChar[[str length]];
    NSRange bufrange;
    bufrange.location=0;
    bufrange.length=[str length];
    if (!buf) { clear(); return this; }
    [str getCharacters:buf range: bufrange];
    // 3rd parameter: what we have in the buffer
    UASSERT(SetEventParameter(event, kEventParamTextInputSendText,
        typeUnicodeText, reallen, buf));
     
    // 4th paramter: "fix" length, >0 if we're dumping ("sending") the buffer
    UASSERT(SetEventParameter(event, kEventParamTextInputSendFixLen,
        typeLongInteger, sizeof(long), &fixlen));

    // set update region
    updaterange=(TextRangeArrayPtr)NewPtrClear(sizeof(short)+
        sizeof(TextRange)*2);
            
    if (!updaterange) return this;   // memory full (unlikely)
    
    updaterange->fNumOfRanges=2;
    updaterange->fRange[0].fStart=0;
    updaterange->fRange[0].fEnd=lastupdate*sizeof(UniChar);
    updaterange->fRange[0].fHiliteStyle=0;
    updaterange->fRange[1].fStart=0;
    updaterange->fRange[1].fEnd=reallen;
    updaterange->fRange[1].fHiliteStyle=0;

    lastupdate=[str length];
    UASSERT(SetEventParameter(event, kEventParamTextInputSendUpdateRng,
        typeTextRangeArray, sizeof(short)+sizeof(TextRange)*2, updaterange));

    markrange=(TextRangeArrayPtr)NewPtrClear(sizeof(short)+
        sizeof(TextRange)*3);
			
    // among the four TSM update messages: k(Selected)RawText and
    // k(Selected)ConvertedText, it seems only the latter pair works,
    // i.e both kSelectedRawText and kRawText seem to be defunct
			
    #define SETRANGE(r, f, e, s) markrange->fRange[r].fStart=f; \
        markrange->fRange[r].fEnd=e; \
        markrange->fRange[r].fHiliteStyle=s
			
    if(!markrange) return this;     // memory full (unlikely)
    
    markrange->fNumOfRanges=2;
    int realcur=reallen;
    
    // if cursor is set (!= -1), we set its position accordingly
    if (cursor>=0 && realPos(cursor)<=(int)[str length]) 
        realcur=realPos(cursor)*sizeof(UniChar);

    // requests app to draw a light gray underline to our text area                
    SETRANGE(0, 0, reallen, kConvertedText);
    SETRANGE(1, realcur, realcur, kCaretPosition);
    
    // if markFrom & markTo are set, draw a darker line underneath the marked area
    if ((markFrom>=0 && realPos(markFrom)<=(int)[str length]) &&
        (markTo>markFrom && realPos(markTo)<=(int)[str length]))
    {
        markrange->fNumOfRanges=3;		// send one more range block 

        SETRANGE(2, realPos(markFrom)*sizeof(UniChar),
            realPos(markTo)*sizeof(UniChar), kSelectedConvertedText); 
    
        fprintf(stderr, "(%d,%d,%d)\n", realPos(markFrom), realPos(markTo), realcur);
    }

            
    UASSERT(SetEventParameter(event, kEventParamTextInputSendHiliteRng,
        typeTextRangeArray,
        sizeof(short)+sizeof(TextRange)*markrange->fNumOfRanges, markrange));

    // we don't any "clause" information
    pinrange.fStart=0;
    pinrange.fEnd=reallen;
    UASSERT(SetEventParameter(event,kEventParamTextInputSendPinRng,
        typeTextRange, sizeof(TextRange), &pinrange));

    UASSERT(SendTextInputEvent(event));      // send event, whew!

    // delete the allocated range objects
    DisposePtr((Ptr)markrange);
    DisposePtr((Ptr)updaterange);
    delete[] buf;
    return this; 
}