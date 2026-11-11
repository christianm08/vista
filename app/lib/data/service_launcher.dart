import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';

const _device = MethodChannel('vista/device');

/// Apre il titolo nel servizio scelto.
///
/// TMDB non fornisce link diretti ai contenuti: su telefono e PC si apre la
/// ricerca del servizio (su Android il link apre l'app, se installata); sulla
/// TV, dove le app di solito non gestiscono i link, si apre l'app. Se non si
/// conosce il servizio si apre la pagina JustWatch con tutte le opzioni.
Future<bool> openService(
  WatchProvider p,
  String title, {
  String fallback = '',
}) async {
  final url = providerSearchUrl(p.name, title, fallback: fallback);
  final packages = providerAndroidPackages(p.name);
  final android = !kIsWeb && Platform.isAndroid;

  if (android &&
      Device.isTv &&
      packages.isNotEmpty &&
      await _openApp(packages)) {
    return true;
  }
  if (url.isNotEmpty) {
    final uri = Uri.parse(url);
    if (android) {
      // Prima l'app che gestisce il link, poi l'app per nome, poi il browser.
      try {
        if (await launchUrl(
          uri,
          mode: LaunchMode.externalNonBrowserApplication,
        )) {
          return true;
        }
      } on PlatformException {
        // nessuna app per il link
      }
      if (packages.isNotEmpty && await _openApp(packages)) return true;
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } on PlatformException {
      // niente browser (es. alcune TV)
    }
  }
  if (android && packages.isNotEmpty) return _openApp(packages);
  return false;
}

/// Apre un indirizzo qualsiasi (trailer, IMDb, JustWatch).
Future<bool> openLink(String url) async {
  if (url.isEmpty) return false;
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } on PlatformException {
    return false;
  }
}

Future<bool> _openApp(List<String> packages) async {
  try {
    return await _device.invokeMethod<bool>('openApp', {
          'packages': packages,
        }) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
