enum Env { local, prod }

class AppConfig {
  static const _env = String.fromEnvironment('ENV', defaultValue: 'prod');

  static Env get env => _env == 'local' ? Env.local : Env.prod;

  static const _localHost =
      String.fromEnvironment('LOCAL_HOST', defaultValue: 'localhost');

  static String get baseUrl => switch (env) {
        Env.local => 'http://$_localHost:8080',
        Env.prod => 'https://meowth-ancient-summit-8275.fly.dev',
      };
}
