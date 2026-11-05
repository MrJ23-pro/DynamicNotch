# DynamicNotch

[English](README.md) | Français

Le Dynamic Island de l'iPhone, mais sur l'encoche du MacBook, pour Spotify.

![DynamicNotch ouvert](docs/preview.png)

Quand un son passe, l'encoche s'élargit un peu : la pochette à gauche de la caméra, un petit égaliseur à droite.

![DynamicNotch fermé](docs/compact.png)

Tu passes la souris dessus et ça s'ouvre avec le titre, l'artiste, la barre de progression et les boutons lecture / pause / suivant / précédent. Quand rien ne joue, ça disparaît dans l'encoche.

## Prérequis

- macOS 14 ou plus récent
- Un Mac avec encoche (sur les autres, ça fait une petite pilule dans la barre des menus)
- Spotify (l'app desktop)
- Les outils de ligne de commande Xcode : `xcode-select --install`

## Télécharger

Prends `DynamicNotch.zip` dans la [dernière release](https://github.com/MrJ23-pro/DynamicNotch/releases/latest), dézippe et glisse `DynamicNotch.app` dans Applications. Mac Apple Silicon uniquement.

L'app n'est pas notarisée, donc macOS la bloque au premier lancement. Soit tu vas dans Réglages Système > Confidentialité et sécurité et tu cliques sur "Ouvrir quand même", soit tu lances :

```bash
xattr -dr com.apple.quarantine /Applications/DynamicNotch.app
```

## Compiler soi-même

```bash
git clone https://github.com/MrJ23-pro/DynamicNotch.git
cd DynamicNotch
./build.sh
open DynamicNotch.app
```

Au premier lancement macOS demande si DynamicNotch peut contrôler Spotify, il faut accepter sinon rien ne s'affiche. Si tu as refusé par erreur : Réglages Système > Confidentialité et sécurité > Automatisation.

Pour qu'il se lance au démarrage, glisse `DynamicNotch.app` dans Applications puis ajoute-le dans Réglages Système > Général > Ouverture.

## Utilisation

- Survoler l'encoche pour l'ouvrir
- Cliquer sur la barre de progression pour avancer dans le son
- Le bouton palette change de thème
- Clic droit sur l'île pour choisir un thème ou quitter

Thèmes dispo : Classique, Pochette, Spotify, Néon, Mono. Le choix est gardé entre deux lancements.

![Les thèmes](docs/themes.png)

## Comment ça marche

Spotify envoie une notification système à chaque changement de son ou de lecture, l'app écoute ça au lieu d'interroger Spotify en boucle. AppleScript sert seulement pour la pochette et les boutons, et tourne hors du thread principal. Du coup l'app est à 0 % de CPU quand on ne la touche pas.

La fenêtre est un `NSPanel` transparent posé au dessus de la barre des menus, qui ne prend les clics que quand la souris est sur l'île.

## Limites

- Spotify uniquement pour l'instant (pas Apple Music)
- Sur plusieurs écrans, l'île reste sur l'écran qui a l'encoche
- Pas notarisée, voir [Télécharger](#télécharger) pour passer Gatekeeper

## Licence

MIT, voir [LICENSE](LICENSE).
