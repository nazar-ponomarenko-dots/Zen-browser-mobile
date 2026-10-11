/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

package app.zen.mobile;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.util.Log;

import org.mozilla.geckoview.GeckoResult;
import org.mozilla.geckoview.GeckoRuntime;
import org.mozilla.geckoview.GeckoSession;
import org.mozilla.geckoview.GeckoSessionSettings;
import org.mozilla.geckoview.GeckoView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

/**
 * Host activity for the standalone Zen/Gecko Android port.
 *
 * <p>M3 variant A: GeckoRuntime owns the Gecko bootstrap (mozglue -> libs ->
 * nativeRun/XRE_main) and a GeckoSession opened with {@code chromeUri} makes
 * GeckoViewSupport::Open hand the XUL browser.xhtml window to this view's
 * LayerView surface (compositor, input and IME come with it).
 */
public class MainActivity extends Activity {

    private static final String LOGTAG = "ZenDroid";
    private static final String CHROME_URI = "chrome://browser/content/browser.xhtml";

    private static final int REQUEST_FILE = 0x2A01;

    // The runtime is per app process; survive Activity recreation.
    private static GeckoRuntime sRuntime;

    private GeckoView mView;
    private GeckoSession mSession;

    // Pending <input type=file> prompt bridged to SAF (zen-android #37).
    private GeckoSession.PromptDelegate.FilePrompt mPendingFilePrompt;
    private GeckoResult<GeckoSession.PromptDelegate.PromptResponse> mPendingFileResult;

    @Override
    protected void onCreate(final Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Log.i(LOGTAG, "MainActivity created; starting Gecko via GeckoRuntime (M3)");
        if (sRuntime == null) {
            sRuntime = GeckoRuntime.create(this);
        }

        mSession =
                new GeckoSession(
                        new GeckoSessionSettings.Builder().chromeUri(CHROME_URI).build());
        mSession.setPromptDelegate(new PromptDelegate());
        // open() is asynchronous and queues until PROFILE_READY.
        mSession.open(sRuntime);

        mView = new GeckoView(this);
        setContentView(mView);
        mView.setSession(mSession);
        Log.i(LOGTAG, "M3: GeckoView attached, chrome session opening for " + CHROME_URI);
    }

    /**
     * Bridges content file pickers to the Storage Access Framework. Gecko side:
     * browser/modules/ZenAndroidFilePicker.sys.mjs sends the standard
     * "GeckoView:Prompt" event, which the geckoview PromptController turns into
     * onFilePrompt here; the picked URIs are materialized to local files
     * before FilePrompt.confirm() hands them to Gecko (zen-android #37).
     */
    private class PromptDelegate implements GeckoSession.PromptDelegate {
        @Override
        public GeckoResult<PromptResponse> onFilePrompt(
                final GeckoSession session, final FilePrompt prompt) {
            if (mPendingFileResult != null) {
                mPendingFileResult.complete(mPendingFilePrompt.dismiss());
            }

            final GeckoResult<PromptResponse> result = new GeckoResult<>();
            mPendingFilePrompt = prompt;
            mPendingFileResult = result;

            final Intent intent;
            if (prompt.type == FilePrompt.Type.FOLDER) {
                intent =
                        new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } else {
                intent =
                        new Intent(Intent.ACTION_OPEN_DOCUMENT)
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                .setType("*/*");
                if (prompt.type == FilePrompt.Type.MULTIPLE) {
                    intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                }
                final String[] mimeTypes = prompt.mimeTypes;
                if (mimeTypes != null && mimeTypes.length > 0) {
                    intent.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes);
                }
            }

            try {
                startActivityForResult(intent, REQUEST_FILE);
            } catch (final Exception e) {
                Log.e(LOGTAG, "cannot open SAF picker", e);
                mPendingFilePrompt = null;
                mPendingFileResult = null;
                result.complete(prompt.dismiss());
            }
            return result;
        }
    }

    @Override
    protected void onActivityResult(
            final int requestCode, final int resultCode, final Intent data) {
        if (requestCode != REQUEST_FILE) {
            super.onActivityResult(requestCode, resultCode, data);
            return;
        }

        final GeckoSession.PromptDelegate.FilePrompt prompt = mPendingFilePrompt;
        final GeckoResult<GeckoSession.PromptDelegate.PromptResponse> result = mPendingFileResult;
        mPendingFilePrompt = null;
        mPendingFileResult = null;
        if (prompt == null || result == null) {
            return;
        }

        final List<Uri> uris = new ArrayList<>();
        if (resultCode == RESULT_OK && data != null) {
            if (data.getData() != null) {
                uris.add(data.getData());
            }
            final ClipData clip = data.getClipData();
            if (clip != null) {
                for (int i = 0; i < clip.getItemCount(); i++) {
                    uris.add(clip.getItemAt(i).getUri());
                }
            }
        }

        if (uris.isEmpty()) {
            result.complete(prompt.dismiss());
            return;
        }

        if (prompt.type == GeckoSession.PromptDelegate.FilePrompt.Type.FOLDER) {
            final Uri tree = uris.get(0);
            try {
                getContentResolver()
                        .takePersistableUriPermission(
                                tree, Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } catch (final SecurityException e) {
                Log.w(LOGTAG, "persistable tree grant failed", e);
            }
            result.complete(prompt.confirm(MainActivity.this, tree));
        } else {
            final Uri[] local = new Uri[uris.size()];
            for (int i = 0; i < uris.size(); i++) {
                local[i] = materializeForGecko(uris.get(i));
            }
            result.complete(prompt.confirm(MainActivity.this, local));
        }
    }

    /**
     * Turns a SAF content:// URI into a file:// URI Gecko can open.
     *
     * <p>FilePrompt.confirm() only resolves content URIs from the external
     * storage document provider to a path (e.g. downloads-provider URIs become
     * null -> NS_ERROR_FILE_UNRECOGNIZED_PATH), and even a resolved
     * /storage/... path is unreadable without a storage permission this app
     * does not declare. Copying through the ContentResolver works for any
     * provider because the URI read grant from the picker is in-process.
     */
    private Uri materializeForGecko(final Uri uri) {
        if (!"content".equals(uri.getScheme())) {
            return uri;
        }

        final File dir =
                new File(getCacheDir(), "uploads/" + System.currentTimeMillis());
        if (!dir.mkdirs() && !dir.isDirectory()) {
            return uri;
        }
        final File out = new File(dir, displayName(uri));
        try (final InputStream in = getContentResolver().openInputStream(uri);
             final OutputStream os = new FileOutputStream(out)) {
            if (in == null) {
                return uri;
            }
            final byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) > 0) {
                os.write(buf, 0, n);
            }
            return Uri.fromFile(out);
        } catch (final Exception e) {
            Log.w(LOGTAG, "cannot copy picked uri " + uri, e);
            return uri;
        }
    }

    private String displayName(final Uri uri) {
        try (final Cursor c =
                getContentResolver()
                        .query(
                                uri,
                                new String[] {OpenableColumns.DISPLAY_NAME},
                                null,
                                null,
                                null)) {
            if (c != null && c.moveToFirst()) {
                final int idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (idx >= 0) {
                    final String name = c.getString(idx);
                    if (name != null && !name.isEmpty()) {
                        return name.replace('/', '_');
                    }
                }
            }
        } catch (final Exception e) {
        }
        return "upload";
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (mPendingFileResult != null) {
            mPendingFileResult.complete(mPendingFilePrompt.dismiss());
            mPendingFilePrompt = null;
            mPendingFileResult = null;
        }
        if (mSession != null) {
            mSession.close();
            mSession = null;
        }
        mView = null;
        Log.i(LOGTAG, "MainActivity destroyed");
    }
}
