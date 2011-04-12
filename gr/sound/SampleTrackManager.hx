package gr.sound;

import flash.events.SampleDataEvent;
import flash.utils.ByteArray;
import flash.utils.Endian;
import flash.media.Sound;
import flash.media.SoundChannel;
import flash.utils.TypedDictionary;
import flash.Memory;
import flash.errors.Error;
import gr.HaxeMemory;

/**
*
* SampleTrackManager manages sounds and mixes them very fast.
* It uses the haxe flash.Memory API  for fast reading and writing of sound data to a preallocated byteArray.  
* 
* This may be incompatible with other haxe classes that require access to flash Memory 
* if they don't have a way to inject a byteArray and memory offset.
*
* Using gr.HaxeMemory.allocate, you can prepare a byteArray for the SampleTrackManager.
* 
* Before sounds can be played you need to run init() to trigger the sampleDataEvent for the 
* internal Sound instance to begin mixing.
*
* Call registerSample to register a Sound class on a 'track' and give it a sample name.
* Tracks are used to organize groups of samples.  There are 3 Tracks: Music, Ambience, and FX.
* 
* You play a sound by calling play() with the sample name and the option for looping. 
* A SampleTrackNode is returned to which you can attach an event listener to listen for when the clip has stopped playing.
* SampleTrackNode's belong to the SampleTrackManager, so only modify the instance if you know what you're doing.
*
* Fade in and out of samples can be controlled by tweening the SampleTrackNode's volume property.
*
* TODO: pausing
*/
class SampleTrackManager {

    public static var SAMPLE_MIN:Int = 2048;
    public static var SOUND_MEMORY:Int = 2048<<3;

    public static var MUSIC:String = "music";
    public static var AMBIENCE:String = "ambience";
    public static var FX:String = "fx";

    public static function allocateMemory():ByteArray {
        return HaxeMemory.allocate(SOUND_MEMORY);
    }

    /**
    * Create a new manager.  If you pass in an optional ByteArray it will check that there's 16KB of memory for mixing
    * @param byteArray optional ByteArray for mixing.  Use with gr.HaxeMemory for fast memory access.
    * @param memoryOffset optional defaults to 0. Used to partition the byteArray (e.g. HaxeMemory).
    */
    public function new(?_bytes:ByteArray = null, ?_memoryOffset:Int = 0) {
        
        m_sound = new Sound();
        m_sound.addEventListener(SampleDataEvent.SAMPLE_DATA, onSampleData);

        m_sampleSize = SampleTrackManager.SAMPLE_MIN;

        if (_bytes == null) {
            m_mixData = new ByteArray();
            m_mixData.endian = Endian.LITTLE_ENDIAN;
            m_mixData.length = SOUND_MEMORY;
        } else {
            m_memoryOffset = _memoryOffset;
            // check that there's enough memory
            m_mixData = _bytes;
            m_mixData.position = m_memoryOffset;
            if (m_mixData.bytesAvailable < SOUND_MEMORY) {
                throw new Error("Not enough memory at " +_memoryOffset+". SampleTrackManager needs "+SOUND_MEMORY+" bytes.");
            }
            if (m_mixData.endian != Endian.LITTLE_ENDIAN) {
                throw new Error("currentDomain's domainMemory endianess must be Endian.LITTLE_ENDIAN");
            }
        }

        Memory.select(m_mixData);

        m_tracks = new TypedDictionary();

        m_trackVolumes = new TypedDictionary();
        m_trackVolumes.set(SampleTrackManager.MUSIC, 1);
        m_trackVolumes.set(SampleTrackManager.AMBIENCE, 1);
        m_trackVolumes.set(SampleTrackManager.FX, 1);

        m_samples = new TypedDictionary();
        m_playing = new TypedDictionary();
        m_paused = new TypedDictionary();

        volume = 1;
    }

    public var volume:Float; // global volume

    // These setters and getters don't work in AS3. Call get/setTrackVolume directly.
    public var musicVolume(getMusicVolume, setMusicVolume):Float;
    public var ambienceVolume(getAmbienceVolume, setAmbienceVolume):Float;
    public var fxVolume(getFxVolume, setFxVolume):Float;

    var m_sound:Sound;
    var m_soundChannel:SoundChannel;
    var m_mixData:ByteArray;
    var m_memoryOffset:Int;
    var m_useDomainMemory:Bool;
    var m_sampleSize:Int; 

    var m_tracks:TypedDictionary<String, SampleTrackNode>;
    var m_trackVolumes:TypedDictionary<String, Float>; 
    var m_samples:TypedDictionary<String, SampleInfo>;
    var m_playing:TypedDictionary<String, SampleTrackNode>;
    var m_paused:TypedDictionary<String, SampleTrackNode>;

    var m_cursor:SampleTrackNode;
    var m_prev:SampleTrackNode;

    public function init():Void {
        m_sound.play();
    }

    public function registerSample(_track:String, _soundClass:Class<Sound>, _sampleName:String):Void {
        m_samples.set(_sampleName, new SampleInfo(_track, _soundClass, _sampleName));
    }

    public function play(_sampleName:String, _loop:Bool = false):SampleTrackNode {
        var sample:SampleInfo = m_samples.get(_sampleName);
        if (sample == null) {
            throw new Error("Could not find '" + _sampleName + "' to play");
        }
        var node:SampleTrackNode = new SampleTrackNode(sample, _loop);

        addNode(sample.track, node);
        m_playing.set(node.id, node);
        return node;
    }

    inline function addNode(_track:String, _node:SampleTrackNode):Void {
        var head:SampleTrackNode = m_tracks.get(_track);
        _node.next = null;
        if (head != null) {
            _node.next = head;
        } 
        m_tracks.set(_track, _node);
    }

    /**
    * onSampleData mixes all the tracks by looping through the each of the nodes and calling the mix method on them.
    * When mix calls returns a 0, the node has finished playback and we call dispatchComplete on it.
    */
    function onSampleData(_e:SampleDataEvent):Void {
        // clear out memory
        for (i in 0...m_sampleSize) {
            Memory.setDouble((i << 3) + m_memoryOffset, 0);    
        }

        // mix the tracks
        var readCount:Int = 0;
        for (track in m_tracks) {
            m_cursor = m_tracks.get(track);
            var trackVolume:Float = volume * m_trackVolumes.get(track);
            m_prev = null;
            while(m_cursor != null) {
                readCount = m_cursor.mix(trackVolume, m_memoryOffset, m_sampleSize);
                if (readCount > 0) {
                    m_prev = m_cursor;
                    m_cursor = m_cursor.next;
                } else {
                    var finNode = m_cursor;
                    if (m_prev != null) {
                        m_prev.next = m_cursor = m_cursor.next;
                    } else {
                        m_cursor = m_cursor.next;
                        m_tracks.set(track, m_cursor);
                    }
                    m_playing.set(finNode.id, null);
                    finNode.dispatchComplete();
                }
            }
        }

        // write the mix data to the SampleDataEvent's byteArray
        _e.data.endian = Endian.LITTLE_ENDIAN;
        _e.data.writeBytes(m_mixData, m_memoryOffset, SOUND_MEMORY);
    }

    // volume functions
    inline public function setTrackVolume(_track:String, _volume:Float):Float {
        m_trackVolumes.set(_track, _volume);
        return _volume;
    }
    inline public function getTrackVolume(_track:String):Float { return m_trackVolumes.get(_track); }

    inline public function getMusicVolume():Float { return getTrackVolume(SampleTrackManager.MUSIC); }
    inline public function setMusicVolume(_vol:Float):Float { return setTrackVolume(SampleTrackManager.MUSIC, _vol); }

    inline public function getAmbienceVolume():Float { return getTrackVolume(SampleTrackManager.AMBIENCE); }
    inline public function setAmbienceVolume(_vol:Float):Float { return setTrackVolume(SampleTrackManager.AMBIENCE, _vol); }

    inline public function getFxVolume():Float { return getTrackVolume(SampleTrackManager.FX); }
    inline public function setFxVolume(_vol:Float):Float { return setTrackVolume(SampleTrackManager.FX, _vol); }

    // checks if a sample is playing
    public function isPlayingById(_id:String):Bool {
        return m_playing.get(_id) != null;
    }

    // checks if a sample is paused
    public function isPausedById(_id:String):Bool {
        return m_paused.get(_id) != null;
    }

    // helpers
        function _trackTestCB(_track:String):SampleTrackNode -> Bool {
            return function(_node:SampleTrackNode):Bool {
                return _track == _node.sample.track;
            }
        }

        function _nameTestCB(_sampleName:String):SampleTrackNode -> Bool {
            return function(_node:SampleTrackNode):Bool {
                return _sampleName == _node.sample.name;
            }
        }

        function _idTestCB(_id:String):SampleTrackNode -> Bool {
            return function(_node:SampleTrackNode):Bool {
                return _id == _node.id;
            }
        }

    // helper function that loops over a track, performs a nodeTest on each node, and if true, performs the nodeTestAction
    // used by the stopLoop, pauseLoop, and maybe future loops for adjusting the speed of playback
        function trackLoop(_track, _nodeTest:SampleTrackNode -> Bool, _nodeTestAction:SampleTrackNode -> Void):Void {
            m_cursor = m_tracks.get(_track);
            m_prev = null;
            while (m_cursor != null) {
                if (_nodeTest(m_cursor)) {
                    _nodeTestAction(m_cursor);
                } else {
                    m_prev = m_cursor;
                    m_cursor = m_cursor.next;
                }
            }
        }

    // stop functions
    // used by the stop functions to stop nodes from playback
    function stopLoop(_track:String, _nodeTest:SampleTrackNode -> Bool):Void {
        trackLoop(_track, _nodeTest, stopNode);
    }
        function stopNode(_node:SampleTrackNode):Void {
            var fin = m_cursor;
            var track = m_cursor.sample.track;

            m_cursor = m_cursor.next;
            if (m_prev != null) {
                m_prev.next = m_cursor;
            } else {
                m_tracks.set(track, m_cursor);
            }
            fin.dispatchComplete();
        }

    // kills all samples
    public function stop():Void {
        for (track in m_tracks) {
            stopTrack(track); 
        }
    }

    // stops a track
    public function stopTrack(_track:String):Void {
        m_cursor = m_tracks.get(_track);
        while (m_cursor != null) {
            var fin = m_cursor;
            m_cursor = m_cursor.next;
            fin.dispatchComplete();
        }
        m_tracks.set(_track, null);
    }

    // stops samples by name
    public function stopByName(_name:String):Void {
        var sample = m_samples.get(_name);
        if (sample != null) {
            stopLoop(sample.track, _nameTestCB(_name));
        }
    }
    

    // stops a sample by SampleTrackNode id
    public function stopById(_id:String):Void {
        if (m_playing.get(_id) != null) {
            stopLoop(m_playing.get(_id).sample.track, _idTestCB(_id));
        }
    }


    // pause functions
    function pauseLoop(_track:String, _nodeTest:SampleTrackNode -> Bool):Void {
        trackLoop(_track, _nodeTest, pauseNode);
    }
        function pauseNode(_node:SampleTrackNode):Void {
            var pNode = m_cursor;
            var track = m_cursor.sample.track;

            m_cursor = m_cursor.next;
            if (m_prev != null) {
                m_prev.next = m_cursor;
            } else {
                m_tracks.set(track, m_cursor);
            }
            pNode.next = null;
            m_paused.set(pNode.id, pNode);
        }

    public function pause():Void {
        for (track in m_tracks) {
            pauseTrack(track);
        }
    }

    public function pauseTrack(_track):Void {
        m_cursor = m_tracks.get(_track);
        while (m_cursor != null) {
            var fin = m_cursor;
            m_cursor = m_cursor.next;
            fin.next = null;
            m_paused.set(fin.id, fin);
        }
        m_tracks.set(_track, null);
    }

    public function pauseByName(_name:String):Void {
        var sample = m_samples.get(_name);
        if (sample != null) {
            pauseLoop(sample.track, _nameTestCB(_name));
        }
    }

    public function pauseById(_id:String):Void {
        if (m_playing.get(_id) != null) {
            pauseLoop(m_playing.get(_id).sample.track, _idTestCB(_id));
        }
    }

    // unpause functions
    function unpauseLoop(_nodeTest:SampleTrackNode -> Bool):Void {
        for (nodeId in m_paused) {
            var node = m_paused.get(nodeId);
            if (node != null && _nodeTest(node)) {
                m_paused.set(node.id, null);
                addNode(node.sample.track, node);
            }
        }
    }

    public function unpause():Void {
        for (track in m_tracks) {
            unpauseTrack(track);
        }
    }

    public function unpauseTrack(_track:String):Void { unpauseLoop(_trackTestCB(_track)); }
    public function unpauseByName(_name:String):Void { unpauseLoop(_nameTestCB(_name)); }
    public function unpauseById(_id:String):Void { unpauseLoop(_idTestCB(_id)); }
}
