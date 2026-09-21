---
layout: home
---

<div class="prose lede" markdown="1">
A menu for the thing NixOS is good at and awkward about: **changing what is
installed**. Search nixpkgs, switch apps and services on, set options from a
form, and rebuild when you are ready. What you get is a NixOS generation, so
it rolls back.
</div>

<div class="hero">
<video controls autoplay loop muted playsinline preload="metadata"
       poster="img/tour-poster.png" width="620" height="474"
       aria-label="A tour of the menu: every tab, a search of nixpkgs, a package queued, and a flake's modules listed">
  <source src="img/tour.webm" type="video/webm">
  <!-- A link, not an <img>: an image here is fetched even when the video
       plays, and the gif is five times the webm. -->
  <a href="img/tour.gif">Watch the tour as a GIF</a>
</video>
<ul class="links">
  <li><a href="https://github.com/olafkfreund/nixarchy-pkg#install">Install</a></li>
  <li><a href="manual/">Read the manual</a></li>
  <li><a href="https://github.com/olafkfreund/nixarchy-pkg">Source</a></li>
</ul>
</div>

<h2>Getting lazygit without opening an editor</h2>
<p>I want lazygit. I don't know whether it's in nixpkgs, and I don't want to
open a <code>.nix</code> file to find out. Every screenshot below is the real
menu on a real laptop, driven from the keyboard.</p>

<section class="scene">
  <a href="img/06-packages-search.png"><img src="img/06-packages-search.png" width="1100" height="842" loading="lazy"
       alt="The Selection tab with lazygit typed in the search field; lazygit is the first result, above yaziPlugins.lazygit and vimPlugins.lazygit-nvim"></a>
  <div>
    <div class="step">1 · Find it</div>
    <h3>Search the whole of nixpkgs</h3>
    <p><code>SUPER ALT N</code> opens the menu, <code>/</code> searches.
    On Selection the search covers every package in nixpkgs, ranked so the
    exact name comes first rather than buried under everything that happens
    to contain it.</p>
  </div>
</section>

<section class="scene">
  <a href="img/05-packages-unfree.png"><img src="img/05-packages-unfree.png" width="1100" height="842" loading="lazy"
       alt="A search for google-chrome: one row, flagged unfree and curated:chrome"></a>
  <div>
    <div class="step">2 · Know what you're adding</div>
    <h3>Flags before you commit to anything</h3>
    <p>A row says when a package is <code>unfree</code>, when nixpkgs marks
    it <code>broken</code>, and when the curated app list already covers it.
    <code>RETURN</code> adds it. Nothing is built yet: adding writes one
    marked line in a file you own.</p>
  </div>
</section>

<section class="scene">
  <a href="img/08-option-form-boolean.png"><img src="img/08-option-form-boolean.png" width="1100" height="842" loading="lazy"
       alt="The option form for services.tailscale.enable: its type (boolean), its description, its default (false), and a toggle"></a>
  <div>
    <div class="step">3 · Set an option</div>
    <h3>A form built from the option's type</h3>
    <p>The Options tab searches NixOS options. <code>RETURN</code> opens a form
    made from the option's declared type: a toggle for a boolean, a list
    editor for a list, its own example to edit when the type has no
    one-word answer. An option you have already set opens on its value.</p>
  </div>
</section>

<section class="scene">
  <a href="img/17-queued.png"><img class="foot" src="img/17-queued.png" width="1100" height="842" loading="lazy"
       alt="A package just added: the footer reads 'hello, added' and '1 change queued'"></a>
  <div>
    <div class="step">4 · See what's waiting</div>
    <h3>Queued, not installed</h3>
    <p>The footer and the bar count what differs between your selection and
    what the system was last built from. It's worked out from the files
    each time rather than remembered, so an edit you make by hand in an editor
    shows up here too.</p>
  </div>
</section>

<section class="scene">
  <a href="img/15-apply-confirm.png"><img class="foot" src="img/15-apply-confirm.png" width="1100" height="842" loading="lazy"
       alt="The apply prompt: 'a again to rebuild the system — any other key cancels', with 1 change queued"></a>
  <div>
    <div class="step">5 · Apply, asked twice</div>
    <h3>One key, then the same key again</h3>
    <p><code>a</code> says what's about to happen and waits, because this
    rebuilds the whole system. A second <code>a</code> starts it, and any
    other key cancels. The build log streams into the menu as plain text,
    and its last line is the result.</p>
  </div>
</section>

<section class="scene scene--text">
  <div>
    <div class="step">6 · Change your mind</div>
    <h3>It's a generation</h3>
    <p>What comes out is an ordinary NixOS generation. If you don't like it,
    boot the previous one or run <code>nixarchy rollback</code>. Nothing
    here replaces NixOS's own safety net. <a href="manual/applying">More on
    applying →</a></p>
  </div>
</section>

<h2>Everything else</h2>
<p>The rest of the menu, one tab at a time.</p>

<div class="grid3">
  <figure>
    <img src="img/01-apps.png" width="1100" height="842" loading="lazy"
         alt="The Apps tab: the curated catalogue, each app with its note or the line it writes">
    <figcaption>Apps: the curated catalogue, on and off.</figcaption>
  </figure>
  <figure>
    <img src="img/03-services.png" width="1100" height="842" loading="lazy"
         alt="The Services tab: flatpak, syncthing, graphics32 and openssh, each with a note">
    <figcaption>Services, with what each one actually does.</figcaption>
  </figure>
  <figure>
    <img src="img/02-apps-filter.png" width="1100" height="842" loading="lazy"
         alt="The Apps tab filtered by 'term': Alacritty, Foot, Ghostty and Kitty">
    <figcaption><code>/</code> filters what's already listed.</figcaption>
  </figure>
  <figure>
    <img src="img/13-flakes.png" width="1100" height="842" loading="lazy"
         alt="The Flakes tab inspecting github:nix-community/nixvim: two nixosModules, seven packages, and module namespaces that exist but cannot be read">
    <figcaption>Flakes: what a flake offers, before you add it.</figcaption>
  </figure>
  <figure>
    <img src="img/14-flake-name-confirm.png" width="1100" height="842" loading="lazy"
         alt="Naming a flake input: the field suggests 'nixvim', and the row reads 'declare github:nix-community/nixvim as inputs.nixvim — RETURN declares, ESC goes back'">
    <figcaption>The input is named from the repo, and you confirm it.</figcaption>
  </figure>
  <figure>
    <img src="img/07-options-search.png" width="1100" height="842" loading="lazy"
         alt="The Options tab searched for tailscale: services.tailscale options, each with its description">
    <figcaption>Every NixOS option, searchable.</figcaption>
  </figure>
</div>

<h2>What it writes</h2>
<div class="prose" markdown="1">
It writes nothing you can't read: every change is one marked line in a file
you own, and every write goes through a script
[nixarchy](https://olafkfreund.github.io/nixarchy/manual/) already ships.

It manages a *selection* rather than your machine, which is the one thing
worth knowing before you start: [why that is, and what it
buys you](manual/how-it-works).
</div>

<footer class="home-foot">
  <a href="https://github.com/olafkfreund/nixarchy-pkg">Source</a> ·
  <a href="manual/">Manual</a> ·
  <a href="https://olafkfreund.github.io/nixarchy/manual/">nixarchy's manual</a>
</footer>
