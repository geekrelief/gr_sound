package gr.sound;

import flash.utils.ByteArray;
import flash.Memory;
import flash.events.Event;
import flash.events.EventDispatcher;

/**
* SampleTrackNode manages an instance of a SampleInfo for mixing into SampleTrackManagers.
* It uses the haxe flash.Memory api for fast calcs on 32-bit floats.
*
* Setting the loop property to true will loop the sample.
* The volume property is used to adjust the volume of the sample.  
*     A value between 0-1 scales the volume betwen (0 and 100%).
* 
* To check when the sample stops playing, attach an event listener for Event.COMPLETE.
* The sample will stop either when stopped from SampleTrackManager or when playback finishes.
*
*/
class SampleTrackNode extends EventDispatcher {
    
    public function new(_sample:SampleInfo, _loop:Bool = false) {
        super();
        init(_sample, _loop);
    }

    /**
    * Used internally by SampleTrackManager to reinitialize the node after pulling it from the pool
    */
    public function init(_sample:SampleInfo, _loop:Bool):Void {
        id = "stn"+(++SampleTrackNode.NextID);
        sample = _sample;
        m_bytes = sample.bytes;
        position = 0;
        loop = _loop;
        next = null;
        volume = 1;
    }

    static var NextID:Int = 0;       // a public id generator

    public var next:SampleTrackNode; // used by SampleTrackManager to create a linked list
    
    public var id:String;            // a public identifier used by the application to manipulate the instance
    public var sample:SampleInfo;    // the sample to mix
    var position:Int;                // tracks the position of the sample for mixing

    /**
    * Controls whether the sample loops
    */ 
    public var loop:Bool;
    /**
    * Controls the volume of the sample in the range from 0-1+ where 1 is 100% (normal volume)
    */
    public var volume:Float;

    
    // convenience variables
    var m_readLength:Int;
    var m_tf:Float;
    var m_i:Int;
    var m_bytes:ByteArray;

    /**
    * mix is an internal function, called by SampleTrackManager so the node can mix data for a track.
    */
    public function mix(_trackVolume:Float, _memoryOffset:Int, _sampleCount:Int):Int {
        var vol = _trackVolume * volume;

        m_bytes.position = position;
        m_readLength = ((m_bytes.bytesAvailable>>3) > _sampleCount) ? _sampleCount : (m_bytes.bytesAvailable>>3);
        for (i in 0...m_readLength) {
            m_i = (i << 3) + _memoryOffset;
            Memory.setFloat(m_i, Memory.getFloat(m_i) + m_bytes.readFloat() * vol);
            Memory.setFloat(m_i + 4, Memory.getFloat(m_i + 4) + m_bytes.readFloat() * vol);
        }

        if (m_bytes.bytesAvailable == 0) { // out of data
            // check for loop or finish
            if (loop) {
                m_bytes.position = 0;
                if (m_readLength < _sampleCount) {
                    for (i in m_readLength..._sampleCount) {
                        m_i = (i << 3) + _memoryOffset;
                        Memory.setFloat(m_i, Memory.getFloat(m_i) + m_bytes.readFloat() * vol);
                        Memory.setFloat(m_i + 4, Memory.getFloat(m_i + 4) + m_bytes.readFloat() * vol);
                    }
                }
            } else {
                return 0;
            }
        }

        position = m_bytes.position;
        return m_readLength;
    }

    inline public function dispatchComplete():Void {
        next = null;
        dispatchEvent(new Event(Event.COMPLETE));
    }
}
