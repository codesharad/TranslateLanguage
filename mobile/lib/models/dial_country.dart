class DialCountry {
  const DialCountry({required this.iso, required this.name, required this.dial});

  final String iso;
  final String name;
  final String dial;

  String get label => '$iso +$dial';
}

const dialCountries = <DialCountry>[
  DialCountry(iso: 'IN', name: 'India', dial: '91'),
  DialCountry(iso: 'US', name: 'United States', dial: '1'),
  DialCountry(iso: 'GB', name: 'United Kingdom', dial: '44'),
  DialCountry(iso: 'AE', name: 'United Arab Emirates', dial: '971'),
  DialCountry(iso: 'SG', name: 'Singapore', dial: '65'),
  DialCountry(iso: 'MY', name: 'Malaysia', dial: '60'),
  DialCountry(iso: 'AU', name: 'Australia', dial: '61'),
  DialCountry(iso: 'CA', name: 'Canada', dial: '1'),
  DialCountry(iso: 'DE', name: 'Germany', dial: '49'),
  DialCountry(iso: 'FR', name: 'France', dial: '33'),
  DialCountry(iso: 'SA', name: 'Saudi Arabia', dial: '966'),
  DialCountry(iso: 'NP', name: 'Nepal', dial: '977'),
  DialCountry(iso: 'BD', name: 'Bangladesh', dial: '880'),
  DialCountry(iso: 'LK', name: 'Sri Lanka', dial: '94'),
];

DialCountry dialCountryByIso(String iso) =>
    dialCountries.firstWhere((c) => c.iso == iso, orElse: () => dialCountries.first);
