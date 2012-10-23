---
layout: post
title: Mobile Detection with Varnish and Drupal
abstract: |
  An outline on how to get Varnish to detect if the user is using a mobile 
  device to access your site and how to have a cache group for each device 
  type. I will also talk about how you can then get Drupal to serve your 
  site with a mobile friendly theme when Varnish detected a mobile device.
authors:
 - <a href="http://sevengoslings.net">Morten Fangel</a>
---

**Update** As per May 1<sup>st</sup>, I've added [Appendix A][appendix-a], to 
discuss a recent blog post that uses WURFL and VCL to detect mobiles.

**Update** As per Oct 21<sup>st</sup>, I've added [Appendix B][appendix-b], to
discuss the new commercial Varnish WURFL plugin by [ScientiaMobile][scientiamobile].

# Motivation: Different Sites for Different Devices

As more and more people starts using smart phones and tablets for their 
browsing needs, it becomes apparent that only having a lightweight mobile
version that doesn't have all content and functionality wont cut it. So
the obvious solution is then to just have a different templates for each 
group of devices you want to cater to. This way all devices can see the 
same information and have the same functionality while you are able to
remove i.e. unwanted blocks from the smaller devices.  
Traditionally this has been accomplished by having the web application
look at the User Agent either via a home-brew set of regular-expressions
or by using a library such as [WURFL][wurfl].  
The drawback to this approach if this is that caching using a reverse-proxy 
such as [Varnish][varnish] impossible because you are now serving different 
markup for the same page. To solve this problem, this paper proposes a 
solution that moves the device detection to the proxy which can then have 
multiple cache groups for the same page, which solves the caching problem. 
When your reverse-proxy queries the backend for a page, it informs which 
device-group it requests the page for. Thus you are currently limited to
choosing one of two: High-performance or pages catered to the users choice of
device.

# Introduction to Device Detection

It is by no means the primary object of this article to describe how a
thorough and robust device detection can be accomplished as this can be
found in other and better articles.  
Device detection is usually accomplished by looking at the User Agent string
that the user sent along with his request. These have no consistent structure 
or in fact any sort of standard definition; User Agent strings are like the
wild west. Despite this, the popular option when it comes to device detection
is still to invent your own set of matching rules. Creating your own matching
rules are fairly prone to giving false positives and not being up to date when
new devices come along.  
A few standard libraries and products have sprung up, that contains a large 
collection of User Agent strings and information of the device that uses that 
particular User Agent string. I've already mentioned [WURFL][wurfl] which is a 
open source project that aims to provide such a database; a commercial 
alternative is [DeviceAtlas][deviceatlas].

A alternative to matching on the User Agent string – or more realistically: an 
additional heuristic – is to check if the device specifies a 
[User Agent Profile][uaprof] (or UAProf). This is usually indicated by the 
`X-WAP-Device` header, that links to a XML-document containing the profile. 
Especially if you are creating your own matching rules this added information
might be useful, as it can tell you details about the device such as screen
resolution etc.

# Device Detection in Varnish

Varnish is configured using the domain specific language [VCL][vcl], which is
fairly basic but does allow for inlining of C code. I haven't been able to 
find a device detection library that has a C-interface – DeviceAtlas has one
for C++ though – so I've chosen to implement a basic device detection through
a small set of regular expressions. My solution is actually just a refinement 
of existing work done by [Audun Ytterdal][ytterdal], which can be found 
[at the Varnish mailing list][ytterdal-link].  
**Update** per Oct 21<sup>st</sup>: *[ScientiaMobile][scientiamobile] has released a commercial Varnish
plugin. Please see [Appendix B][appendix-b] for a discussion on it.*  
As previously mentioned, creating your own matching isn't optimal from a 
maintainability nor from a accuracy viewpoint, but it will have to do. If I
were to improve on the solution it would be to move over to using an 
established library for device detection instead of custom matching rules.

I've chosen to sort my devices into 4 different groups:

* PCs
* Smartphones (i.e. phones with a touch interface)
* Tablets
* Other mobile devices

In my opinion I would rather risk not detecting a mobile device, than falsely
classify a computer as a mobile device. Because of this, I have chosen a 
default classification of PC, and then only when certain that I'm dealing with
a device from one of the other groups, change my guess.  
To implement this in VCL, subroutine called `identify_device` is created,
which will add a made-up header called `X-Device` to the request. This header 
is used to track what device it detected, but also serves as our way of
informing the backend-server of which device was detected. 

{% highlight bash %}
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
{% endhighlight %}

This subroutine needs to be called in the `recv` routine in your VCL-file, 
which could look something like this

{% highlight bash %}
sub vcl_recv {
  # First call our identify_device subroutine to detect the device
  call identify_device;	

  # Your existing recv-routine here
}
{% endhighlight %}

Now Varnish can detect our device for us, and inform the back-end of what type
of device it wants the page generated for. We haven't, however, solved the
main problem: That all devices shares a common cache in Varnish, and hence
will serve all requests but the first as if it was meant for whatever device
first visited this page.  
The way Varnish handles cache-groups is by storing the cache by a hash value
computed by the `hash` routine. So if we add something to the this routine 
that differentiates the different devices, we will effectively have created 
different caches for each device.

{% highlight bash %}
sub vcl_hash { 
  # Your existing hash-routine here..

  # And then add the device to the hash (if its a mobile device)
  if (req.http.X-Device ~ "^mobile") {
    set req.hash += req.http.X-Device; 
  }
}
{% endhighlight %}

Great! Now we've created all the configuration we need for Varnish; It detects
the device, informs the backend and stores the cache for each device type
independently from the other.  
However, I wasn't impressed in how messy my solution looked, especially when I
had a large existing `recv` and `hash` routines. So I set about moving all the
device-detection and hash-addition to a seperate file. The reason why you're 
able to do this, is because of the way Varnish handles multiple definitions of
the same routine. If the first definition of the routine doesn't return 
anything, the next definition is called, etc. So I created a file consisting
of the bare minimum, and made sure that my `recv` and `hash` routines didn't
return anything.

The result was the file [`device-detect.vcl`][device-detect.vcl], which you 
can just include in the top of your existing Varnish configuration file like 
this: 

{% highlight bash %}
include "/path/to/device-detect.vcl";
{% endhighlight %}

# Theme Switching in Drupal

To let the webserver serve a different appearing website to different devices,
we need some sort of functionality to let our webapplication change it's
appearance.  
In the article I'll describe how to do it in [Drupal 7][drupal], the latest
version of a popular open source PHP CMS. I've chosen to do so in the most
lightweight way I could. Another alternative could be to create a module
that interfaces with the [Mobile Tools][mobile-tools] plugin. 

In Drupal 7, there is a simple hook your module can implement called
[`hook_custom_theme`][hook_custom_theme], which allows you to override the
theme for the current page view.  
Basically you can create a module which implements this hook and depending
on what value it receives in the `X-Device` header, change the theme.

{% highlight php %}
<?php
function mymodule_custom_theme() {
  if (isset($_SERVER['HTTP_X_DEVICE'])) {
    switch ($_SERVER['HTTP_X_DEVICE']) {
      case 'mobile-tablet':
        // Show the tablet-theme
        return 'my-tablet-theme';

      case 'mobile-smart':
        // Show the smartphone-theme
        return 'my-smartphone-theme';

      case 'mobile-other':
        // Show our theme for other mobile devices
        return 'my-mobile-theme';
    }
  }
}
?>
{% endhighlight %}

Of course you can extend this to allow you to configure the themes in your 
`settings.php` file if you want.  
You could create your hook like this:

{% highlight php %}
<?php
function mymobile_custom_theme() {
  if (isset($_SERVER['HTTP_X_DEVICE'])
   && strstr($_SERVER['HTTP_X_DEVICE'], 'mobile')) {
    // We're dealing with a mobile device..

    // Remove "mobile_" from the device-string
    $group = substr($_SERVER['HTTP_X_DEVICE'], 7));

    // Look up the configuration variable..
    return variable_get('mobile_theme_' . $group, NULL);
  }
}
?>
{% endhighlight %}

This allows you to add the following to your settings.php

{% highlight php %}
<?php
$conf['mobile_theme_tablet'] = 'my-tablet-theme';
$conf['mobile_theme_smart']  = 'my-smartphone-theme';
$conf['mobile_theme_other']  = 'my-mobile-theme';
?>
{% endhighlight %}

This will allow you to switch the appearance of your site depending on what
device Varnish detected. 

So now we have a Drupal site that is cached by Varnish with different themes
for different devices types. We've gotten the solution we wanted.

# Further Work

As I see it, the solution I've outline in this article has two shortcomings:

1. My solution uses a custom set of matching rules instead of a established
library.  
I would really like it if a library for device detection could be used 
instead of a set of regular expressions, such that only grouping known 
devices into the groups you want, needs to be preformed in Varnish. I 
haven't, however, been able to find any device detection library with a C 
interface that I could try and inline in the VCL configuration.  
**Update** See [Appendix A][appendix-a] for a discussion on a blog post that 
proposes just this.

2. It doesn't incorporate with the [Mobile Tools][mobile-tools] plugin for
Drupal 7 like it should.  
If a module was created where Varnish could serve as a device detection 
method and the various groups could lead to different configurable themes
it would be a much better user experience for anyone using this solution to
device detection.

These two things together would form a great contribution to the Drupal high 
performance eco-system. 

# Conclusion 

It's fairly well known that if you need to run a site with large amounts of 
traffic on Drupal, you need some sort of reverse-proxy caching. Varnish is 
perfect for this job, and modules already exists for Drupal that ties cache 
flushing in Drupal with purging in Varnish etc. In the future, it's likely 
we'll see more and more sites who wants to cater to their mobile clients with 
full, albeit different appearing, access to their normal site. These are 
currently conflicting goals, as the current technologies for changing the 
appearance of your Drupal site works by detecting the device on the 
application server. Any reverse-proxy will then incorrectly group the 
different versions of the same page as one leading to serving a possibly 
incorrect looking page to future visitors.

The solution outlined in this article, especially if made in to a proper 
module with a decent user-experience, is a great way to achieve both these 
goals. You are able to use Varnish to cache your site while still maintaining 
the ability to serve different sites to different devices. Thus we have 
achieved our goal: High-performance coupled with pages catered to the users 
device.

# Appendix A: Varnish and WURFL.

[Dave Hall][davehall-twitter] recently pointed me in the direction of a
Feb. 2011 blog post titled 
[*Mobile Device Detection with WURFL and Varnish*][enrise-blog-post] by
[Enrise][enrise]. It outlines a solution where they load the WURFL XML file
into memory and queries it with xPath. They rely on the assumption that if
the User-Agent is listed in WURFL it's a mobile device. This is a reasonably
assumption, but I would like to have seen WURFL put to a better use than a
simple hit-or-miss check.  
Specifically I miss the possibility of detection different groupings of devices,
namely tablets and smartphones. A tablet and a smartphone has radically 
different screen solutions and in my mind therefore shouldn't be using the same
layout. So if the WURFL solution should be any good it shouldn't just check for
an existing User-Agent in the WURFL file, it should use the attributes 
associated with each device and then return the type of device.

Also, according to the comments on the post, a better way of loading shared
libraries into Varnish than what the author uses exists. So if an improved 
version should be created the loading mechanism should also be updated.

Despite these shortcomings I see the post as a very promising start to what
could become a great Varnish plugin. My own C skills are minimal, so I wouldn't
attempt to take on the task but if anyone is, I would support it in any way I
could.

# Appendix B: Varnish and WURFL Done Right.

[Luca Passani][luca-passani-wikipedia], the creator of WURFL, from 
[ScientiaMobile][scientiamobile] contacted me about the availability of a 
WURFL Module for Varnish. ScientiaMobile have created plugins for 
Varnish, Apache and Nginx that allows you to write configurations that leverages 
the device information contained in WURFL. Their product is, as I'm writing 
this, still in beta but should be released very soon. Passanis blog post titled
[*HTTP and Mobile: The Missing Header*][scientiamobile-blog-post] contains more 
information.
 
I was offered access to an early version of the Varnish module so I could test 
it out and give feedback. So I can confirm that it does exactly what it says on 
the tin. It looks up the device information in WURFL, so you can make Varnish 
act on all the different capabilities of the device through standard VCL files.  
The module will need to look up a device in WURFL the first time a new 
User-Agent is encountered. Any subsequent visits by clients with the same 
User-Agent string will fetch the capabilities from a built in cache so there is 
virtually no impact on response time.

Differently from [Enrises][enrise] solution previously discussed in 
[Appendix A][appendix-a], ScientiaMobile's module will expose the full set of 
WURFL capabilities and Varnish can be configured to act depending on their 
values. Even for a use-case as simple as grouping your clients into three buckets 
– desktop, tablet or mobile – using WURFL might make sense. Keeping track of 
which clients are, and which are not, tablets is a mess and you need very 
specific (and always changing) rules for identification.  This is where the 
capabilities of WURFL is handy. With WURFL you can just refer to the 
self-explanatory capability `is_tablet`. In other words, ScientiaMobile – 
through their work on WURFL – have already done the hard work of classifying 
devices on a large amount of different capabilities. The simplest of these are 
the two boolean capabilities `is_wireless_device` and `is_tablet`. But you also 
have more interesting capabilities like `pointing_method`, `https_support`, 
`resolution_width` or `pdf_support`. So you can tailor your sites to phones that 
uses a touch-screen if that is what they have. Or you can disallow login on 
phones that doesn't support https. The possibilities are endless.

So in short, if you want to serve different sites – or markup – to your clients
depending on the capabilities of the device, this seems like a great way to go
about achieving that goal.

[wurfl]: http://wurfl.sourceforge.net/ "Wireless Universal Resource File"
[varnish]: http://www.varnish-cache.org/ "Varnish Cache"
[deviceatlas]: http://deviceatlas.com/ "DeviceAtlas"
[uaprof]: http://www.openmobilealliance.org/tech/affiliates/wap/wap-248-uaprof-20011020-a.pdf "User Agent Profile specification"
[vcl]: http://www.varnish-cache.org/trac/wiki/VCL "Varnish Documentation on VCL"
[ytterdal]: http://audun.ytterdal.net/ "Audun Ytterdal"
[ytterdal-link]: http://www.varnish-cache.org/lists/pipermail/varnish-misc/2010-April/004103.html "Audun Ytterdal initial solution"
[device-detect.vcl]: /code/device-detect.vcl "Download device-detect.vcl"
[drupal]: http://drupal.org "Drupal"
[mobile-tools]: http://drupal.org/project/mobile_tools "Mobile Tools Project Page on Drupal.org"
[hook_custom_theme]: http://api.drupal.org/api/drupal/modules--system--system.api.php/function/hook_custom_theme/7 "Drupal Documentation on hook_custom_theme"
[appendix-a]: #appendix_a_varnish_and_wurfl "Appendix A: Varnish and WURFL"
[appendix-b]: #appendix_b_varnish_and_wurfl_done_right "Appendix B: Varnish and WURFL Done Right"
[davehall-twitter]: http://twitter.com/skwashd "Dave Halls Twitter profile"
[enrise-blog-post]: http://www.enrise.com/2011/02/mobile-device-detection-with-wurfl-and-varnish/ "Mobile Device Detection with WURFL and Varnish – Enrise"
[enrise]: http://www.enrise.com/ "Enrise"
[scientiamobile-blog-post]: http://www.scientiamobile.com/blog/post/view/id/25/title/HTTP-and-Mobile%3A-The-Missing-Header- "HTTP and Mobile: The Missing Header"
[scientiamobile]: http://www.scientiamobile.com "ScientiaMobile"
[luca-passani-wikipedia]: http://en.wikipedia.org/wiki/Luca_Passani "Luca Passani on Wikipedia"