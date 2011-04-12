import flash.display.Sprite;
import flash.Memory;
import flash.utils.ByteArray;
import flash.utils.Endian;
import flash.events.Event;
import flash.events.MouseEvent;
import flash.system.ApplicationDomain;
import gr.sound.SampleTrackNode;
import gr.sound.SampleTrackManager;


class Main extends Sprite{
    static function main(){
        var m = new Main();
        flash.Lib.current.addChild(m);
    }

    var stm:SampleTrackManager;
    public function new() {
        super();
        addEventListener(Event.ADDED_TO_STAGE, init);
    }

    static var BREAK:String = "break";
    static var SELECT:String = "select";

    //var bytes:ByteArray;
    function init(_e:Event):Void {

        // Allocate haxe Memory for the SampleTrackManager
        //bytes = gr.HaxeMemory.allocate(8192<<3);
        
        // If haxe Memory were allocated elsewhere in your program for other classes, then specify an offset into it
        // with at least 16KB memory for sound mixing.
        //var soundMemoryOffset:Int = 512;
        //stm = new SampleTrackManager(bytes, soundMemoryOffset);

        var soundMemoryOffset:Int = 0;

        stm = new SampleTrackManager(SampleTrackManager.allocateMemory(), soundMemoryOffset);
        stm.registerSample(SampleTrackManager.MUSIC, Break, BREAK); // register a sample on the fx track
        stm.registerSample(SampleTrackManager.AMBIENCE, Select, SELECT); // register a sample on the ambience track
        stm.init();

        createCircle(100, 100, 0xff0000, mdown, mup);
        createCircle(300, 100, 0x00ff00, vup, null);
        createCircle(500, 100, 0x0000ff, vdown, null);
        createCircle(300, 300, 0xff00ff, tdown, null);
        createCircle(100, 500, 0xffff00, pdown, pup);
        createCircle(300, 500, 0xeeaa22, sdown, null);
        stm.musicVolume = 0.5;
    }

    function createCircle(_x:Float, _y:Float, _color:UInt, _down:MouseEvent->Void, _up:MouseEvent->Void):Void {
        var s = new Sprite();
        s.graphics.beginFill(_color);
        s.graphics.drawCircle(_x, _y, 100);
        s.graphics.endFill();
        if (_down != null)
            s.addEventListener(MouseEvent.MOUSE_DOWN, _down);
        if (_up != null)
            s.addEventListener(MouseEvent.MOUSE_UP, _up);
        addChild(s);
    }

    var breakStn:SampleTrackNode;
    function mdown(_e:MouseEvent):Void {
        breakStn = stm.play(BREAK);
        breakStn.volume = 0.5; // adjust this instance's volume
        breakStn.addEventListener(Event.COMPLETE, onFinished); // listen for when it finishes to play another sample
    }

    function onFinished(_e:Event):Void {
        var stn:SampleTrackNode = cast _e.target;
        stn.removeEventListener(Event.COMPLETE, onFinished);
        trace("finished "+stn.sample.name);
        var fstn = stm.play(SELECT);
        trace('fstn '+fstn.id);
    }

    function mup(_e:MouseEvent):Void {
        stm.stopById(breakStn.id);
    }

    function vup(_e:MouseEvent):Void {
        trace('before '+stm.getTrackVolume(SampleTrackManager.MUSIC));
        stm.musicVolume += 0.1;
        trace('after '+stm.getTrackVolume(SampleTrackManager.MUSIC));
    }

    function vdown(_e:MouseEvent):Void {
        trace('before '+stm.getTrackVolume(SampleTrackManager.MUSIC));
        stm.musicVolume -= 0.1;
        trace('after '+stm.getTrackVolume(SampleTrackManager.MUSIC));
    }

    var toggle:Bool;
    var tStn:SampleTrackNode;
    function tdown(_e:MouseEvent):Void {
        if (!toggle) {
            for(i in 0...3) { // play 3 sounds synchronized
                tStn = stm.play(BREAK, true); // loop
                tStn.volume = 1/3.0; // each contributing 1/3 of their volume to mix
            }
        } else {
            stm.stopByName(BREAK);  // stop them all on next clicking
        }
        toggle = !toggle;
    }

    function pdown(_e:MouseEvent):Void {
        stm.pause();
    }

    function pup(_e:MouseEvent):Void {
        stm.unpause();
    }

    var sStn:SampleTrackNode;
    function sdown(_e:MouseEvent):Void {
        if (sStn == null || (!stm.isPlayingById(sStn.id))) {
            // if not playing, play
            sStn = stm.play("select");
        } else if (stm.isPlayingById(sStn.id)) {
            if (stm.isPausedById(sStn.id)) {
                stm.unpauseById(sStn.id);
            } else {
                stm.pauseById(sStn.id);
            }
        } 
    }
}
