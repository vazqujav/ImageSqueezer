threeSixty = {
    init: function() {
	// BEISPIEL:
	//  this._vr = new AC.VR('viewer', '/safaridemos/showcase/threesixty/images/optimized/Seq_v04_640x378_##.jpg', 72, {
        this._vr = new AC.VR('viewer', 'pics/Clinique-360Grad-##.jpg', 50, {
            invert: true
        });
    },
    didShow: function() {
        this.init();
    },
    willHide: function() {
        recycleObjectValueForKey(this, "_vr");
    },
    shouldCache: function() {
        return false;
    }
}
if (!window.isLoaded) {
    window.addEventListener("load", function() {
        threeSixty.init();
    }, false);
}
