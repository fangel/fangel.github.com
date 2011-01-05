#
# A simple mobile device detection implementation in VCL
# http://fangel.github.com/mobile-detection-varnish-drupal
#
# The file is based upon initial work done by Audun Ytterdal, which can be
# found at 
# http://www.varnish-cache.org/lists/pipermail/varnish-misc/2010-April/004103.html
#  
# Usage:
# Include in the top of your existing Varnish configuration like so:
# include "/path/to/device-detect.vcl";
#
# Author:  Morten Fangel <fangel@sevengoslings.net>
# License: MIT License
#
# Copyright (c) 2011 Morten Fangel
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

# Call the Identify Device subrutine in recv
sub vcl_recv {
	call identify_device;
}

# Rutine to try and identify device
sub identify_device { 
	# Default to thinking it's a PC
	set req.http.X-Device = "pc"; 
	
	if (req.http.User-Agent ~ "iPad" ) {
		# It says its a iPad - so let's give them the tablet-site
		set req.http.X-Device = "mobile-tablet";
	}
	
	elsif (req.http.User-Agent ~ "iP(hone|od)" || req.http.User-Agent ~ "Android" ) { 
		# It says its a iPhone, iPod or Android - so let's give them the touch-site..
		set req.http.X-Device = "mobile-smart"; 
	}
	
	elsif (req.http.User-Agent ~ "SymbianOS" || req.http.User-Agent ~ "^BlackBerry" || req.http.User-Agent ~ "^SonyEricsson" || req.http.User-Agent ~ "^Nokia" || req.http.User-Agent ~ "^SAMSUNG" || req.http.User-Agent ~ "^LG") { 
		# Some other sort of mobile
		set req.http.X-Device = "mobile-other"; 
	}  
} 

# Add the device to the hash (if its a mobile device)
sub vcl_hash { 
	if (req.http.X-Device ~ "^mobile") {
		set req.hash += req.http.X-Device; 
	}
}
