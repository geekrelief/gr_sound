package gr;

import flash.utils.ByteArray;
import flash.utils.Endian;
import flash.system.ApplicationDomain;
import flash.errors.Error;
import flash.Memory;

/**
* This class allocates memory and assigns it to the current domain's domainMemory
* It's used with classes that use haxe's flash.Memory API for performance.
*/
class HaxeMemory {
    /**
    * allocate memory and assign it to the current domain's domainMemory
    */
    public static function allocate(_length:Int) {
        if (_length < 0) {
            throw new Error("Memory length must be greater than 0.");
        }

        var bytes = new ByteArray();
        bytes.length = _length;
        bytes.endian = Endian.LITTLE_ENDIAN;
        ApplicationDomain.currentDomain.domainMemory = bytes;
        Memory.select(bytes);
        return bytes;
    }
}

