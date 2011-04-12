package gr.sound;

import flash.media.Sound;
import flash.utils.ByteArray;
import flash.utils.Endian;

/**
* SampleInfo is an internal class used by SampleTrackManager for mixing sounds.
* Calling SampleTrackManager's registerSample creates instances of 
* SampleInfo which are used my SampleTrackNode for mixing.
*/
class SampleInfo {

    public var name:String;
    public var track:String;
    public var bytes:ByteArray;

    public function new(_track:String, _soundClass:Class<Sound>, _sampleName:String) {
        track = _track;
        name = _sampleName;

        var sound = Type.createInstance(_soundClass, []);
        bytes = new ByteArray();
        bytes.endian = Endian.LITTLE_ENDIAN;
        sound.extract(bytes, sound.length * 441);
        bytes.position = 0;
    }
}
