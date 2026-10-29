package com.bradcowdrey.twodegrees.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bradcowdrey.twodegrees.Brand
import com.bradcowdrey.twodegrees.R

/**
 * Terms of Use and Privacy: asked once, and again whenever Brand.TERMS_VERSION changes (the same
 * version as the Mac and iPhone). It stays until the person agrees; Back leaves the app.
 */
@Composable
fun TermsScreen(onAgree: () -> Unit) {
    val ui = Metrics(1f, Inter)
    val uri = LocalUriHandler.current
    Box(Modifier.fillMaxSize().background(Palette.bg).systemBarsPadding(), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 520.dp).fillMaxSize().padding(horizontal = 24.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Spacer(Modifier.weight(1f))
            Image(painterResource(R.drawable.app_mark), null, Modifier.size(56.dp).clip(RoundedCornerShape(13.dp)))
            Text("Terms of Use and Privacy", style = ui.text(28f, FontWeight.SemiBold))
            Text(Brand.TERMS_SUMMARY, style = ui.text(17f).copy(color = Palette.textSecondary))
            Text(
                "By choosing I Agree and using ${Brand.APP_NAME}, you agree to the Terms of Use and Privacy at bradcowdrey.com/legal.",
                style = ui.text(15f).copy(color = Palette.textMuted),
            )
            Spacer(Modifier.weight(1f))
            Box(
                Modifier.fillMaxWidth().heightIn(min = 50.dp).clip(CircleShape).background(Palette.cream)
                    .clickable(role = Role.Button, onClick = onAgree),
                contentAlignment = Alignment.Center,
            ) { Text("I Agree", style = ui.text(17f, FontWeight.SemiBold).copy(color = Palette.bg)) }
            Box(
                Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(role = Role.Button) { uri.openUri(Brand.LEGAL) },
                contentAlignment = Alignment.Center,
            ) { Text("Read the Terms", style = ui.text(17f, FontWeight.Medium).copy(color = Color.White)) }
        }
    }
}
