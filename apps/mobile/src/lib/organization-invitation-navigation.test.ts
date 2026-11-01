import { getNavigationConfig } from 'expo-router/build/getLinkingConfig';
import { getRoutes } from 'expo-router/build/getRoutes';
import { getStateFromPath } from 'expo-router/build/fork/getStateFromPath';
import { inMemoryContext } from 'expo-router/build/testing-library/context-stubs';

import { invitationExitHref } from '@/lib/organization-invitation-flow';

/**
 * Leaving the Invitation screen must target a route that exists in the
 * session's navigator. Resolved here with Expo Router's own route tree built
 * from the real `src/app` file list (screens stubbed), because a mocked router
 * accepts any href. `Stack.Protected` removes `(app)` while signed out and
 * `(auth)` while signed in, so a target in the removed group is dropped.
 */
// Jest runs under Node; the app has no Node typings, so only what is used is typed.
declare const __dirname: string;
type DirectoryEntry = { name: string; isDirectory(): boolean };
const fs = jest.requireActual('fs') as {
  readdirSync(directory: string, options: { withFileTypes: true }): DirectoryEntry[];
};
const path = jest.requireActual('path') as {
  join(...segments: string[]): string;
  resolve(...segments: string[]): string;
};

function routeFiles(directory: string, prefix = '.'): string[] {
  return fs
    .readdirSync(directory, { withFileTypes: true })
    .flatMap((entry) =>
      entry.isDirectory()
        ? routeFiles(path.join(directory, entry.name), `${prefix}/${entry.name}`)
        : /\.tsx?$/.test(entry.name) && !entry.name.includes('+native-intent')
          ? [`${prefix}/${entry.name}`]
          : [],
    );
}

const app = path.resolve(__dirname, '../app');
const context = inMemoryContext(
  Object.fromEntries(routeFiles(app).map((file) => [file, { default: () => null }])),
);
const routes = getRoutes(context as never, { platform: 'android', skipGenerated: true } as never);
const config = getNavigationConfig(routes!, true, { sitemap: false, notFound: false } as never);

function topGroup(href: string): string | undefined {
  const state = getStateFromPath(href, config as never);
  return state?.routes[0]?.state?.routes[0]?.name;
}

describe('leaving the Organization Invitation screen', () => {
  it('cannot use `/`: it always resolves to the signed-in group, which is absent while signed out', () => {
    expect(topGroup('/')).toBe('(app)');
  });

  it('leaves to the landing of the current session', () => {
    expect(invitationExitHref(false)).toBe('/(auth)');
    expect(topGroup(invitationExitHref(false))).toBe('(auth)');
    expect(invitationExitHref(true)).toBe('/(app)');
    expect(topGroup(invitationExitHref(true))).toBe('(app)');
  });
});
